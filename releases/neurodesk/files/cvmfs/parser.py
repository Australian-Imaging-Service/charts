#!/usr/bin/env python3
import csv
import re
import subprocess
import time
import os
import requests
from collections import defaultdict
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

NAMESPACE = os.environ.get('NAMESPACE', 'mounts')
POLL_INTERVAL = 30           # seconds between checks
IDLE_CHECKS_REQUIRED = 2     # consecutive zero-delta readings before flush (60s idle)
MAX_TRACE_LINES = 100000     # wipe trace file after this many lines

# Only track delta FUSE operation counters for idle detection.
# These represent actual user file access. Exclude statfs (system health checks)
# and all absolute/cache/download/catalog metrics (background CVMFS housekeeping).
IDLE_METRIC_PREFIXES = (
    'cvmfs_metrics_delta_cvmfs_n_fs_open',
    'cvmfs_metrics_delta_cvmfs_n_fs_read',
    'cvmfs_metrics_delta_cvmfs_n_fs_lookup',
    'cvmfs_metrics_delta_cvmfs_n_fs_dir_open',
    'cvmfs_metrics_delta_cvmfs_n_fs_readlink',
)


class PodState:
    """Per-pod tracking state for incremental trace file reading."""
    def __init__(self):
        self.last_line_read = 0
        self.leftover_line = None


class TraceParser:
    def __init__(self):
        self.module_counts = defaultdict(int)
        self.pod_states = {}  # pod_name -> PodState
        self.idle_count = 0
        self.pending_flush = False

    # ── pod discovery ─────────────────────────────────────────────────

    def get_all_nodeplugin_pods(self):
        """Get list of all CVMFS nodeplugin pod names."""
        try:
            cmd = (
                f"kubectl get pods -n {NAMESPACE} "
                f"-l app=cvmfs-csi,component=nodeplugin "
                f"-o jsonpath='{{.items[*].metadata.name}}'"
            )
            result = subprocess.run(
                cmd, shell=True, check=True,
                capture_output=True, text=True, timeout=15
            )
            pods = result.stdout.strip().split()
            if pods and pods != ['']:
                print(f"Found {len(pods)} nodeplugin pods: {', '.join(pods)}")
                # Initialize state for any new pods
                for pod in pods:
                    if pod not in self.pod_states:
                        self.pod_states[pod] = PodState()
                # Clean up state for pods that no longer exist
                for old_pod in list(self.pod_states.keys()):
                    if old_pod not in pods:
                        del self.pod_states[old_pod]
                return pods
            return []
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            print(f"Failed to get nodeplugin pods: {e}")
            return []

    # ── idle detection via telegraf metrics (no kubectl exec) ────────

    def get_fuse_deltas(self):
        """Fetch only delta FUSE operation counters from telegraf at localhost:9001.

        Returns a dict of metric_name -> value for IDLE_METRIC_PREFIXES only,
        filtering to the neurodesk repo. Returns None on error.
        """
        try:
            response = requests.get("http://localhost:9001/metrics", timeout=5)
            if response.status_code != 200:
                return None
            deltas = {}
            for line in response.text.split('\n'):
                if line.startswith('#') or not line.strip():
                    continue
                if not any(line.startswith(p) for p in IDLE_METRIC_PREFIXES):
                    continue
                # Only track the neurodesk repo, not cvmfs-config.cern.ch
                if 'neurodesk.ardc.edu.au' not in line:
                    continue
                parts = line.rsplit(' ', 1)
                if len(parts) == 2:
                    try:
                        deltas[parts[0]] = float(parts[1])
                    except (ValueError, IndexError):
                        continue
            return deltas if deltas else None
        except Exception as e:
            print(f"Error fetching metrics: {e}")
            return None

    def is_cvmfs_idle(self):
        """True after IDLE_CHECKS_REQUIRED consecutive readings with all delta FUSE counters at 0.

        Uses delta metrics (change since last CVMFS telemetry report), so when
        CVMFS is idle all values are 0. No need to compare snapshots.
        Note: telegraf aggregates metrics from all nodeplugin pods, so this
        reflects cluster-wide FUSE activity.
        """
        deltas = self.get_fuse_deltas()

        if deltas is None:
            self.idle_count = 0
            return False

        all_zero = all(v == 0 for v in deltas.values())
        total_ops = sum(deltas.values())

        if all_zero:
            self.idle_count += 1
            print(f"CVMFS idle (all FUSE deltas=0), check {self.idle_count}/{IDLE_CHECKS_REQUIRED}")
        else:
            if self.idle_count > 0:
                print(f"CVMFS active (FUSE ops={total_ops:.0f}), resetting idle counter")
            self.idle_count = 0
            self.pending_flush = True

        return self.idle_count >= IDLE_CHECKS_REQUIRED

    # ── kubectl exec operations (only called when idle) ─────────────

    def flush_cvmfs_buffer(self, pod_name, repo):
        try:
            cmd = (
                f"kubectl exec -n {NAMESPACE} {pod_name} -c automount -- "
                f"cvmfs_talk -i {repo} tracebuffer flush"
            )
            subprocess.run(cmd, shell=True, check=True, capture_output=True, timeout=30)
            print(f"Flushed buffer for {repo} on {pod_name}")
            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to flush buffer for {repo} on {pod_name}: {e}")
        except subprocess.TimeoutExpired:
            print(f"Flush timed out for {repo} on {pod_name}")
        return False

    def wipe_trace_file(self, pod_name, repo):
        try:
            cmd = (
                f"kubectl exec -n {NAMESPACE} {pod_name} -c automount -- "
                f"sh -c 'true > /tmp/cvmfs-trace-{repo}.log'"
            )
            subprocess.run(cmd, shell=True, check=True, capture_output=True, timeout=30)
            print(f"Wiped trace file for {repo} on {pod_name}")
            state = self.pod_states.get(pod_name)
            if state:
                state.last_line_read = 0
                state.leftover_line = None
        except subprocess.CalledProcessError as e:
            print(f"Failed to wipe trace file for {repo} on {pod_name}: {e}")
        except subprocess.TimeoutExpired:
            print(f"Wipe timed out for {repo} on {pod_name}")

    def _get_trace_line_count(self, pod_name, repo):
        """Get current line count of trace file to detect nodeplugin restarts."""
        try:
            cmd = (
                f"kubectl exec -n {NAMESPACE} {pod_name} -c automount -- "
                f"wc -l /tmp/cvmfs-trace-{repo}.log"
            )
            result = subprocess.run(
                cmd, shell=True, check=True,
                capture_output=True, text=True, timeout=15
            )
            return int(result.stdout.strip().split()[0])
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError):
            return -1

    def get_new_trace_lines(self, pod_name, repo):
        """Read only lines added since last_line_read using tail."""
        state = self.pod_states.get(pod_name)
        if not state:
            return []
        try:
            # Detect nodeplugin restart: file is shorter than our tracked position
            if state.last_line_read > 0:
                file_lines = self._get_trace_line_count(pod_name, repo)
                if file_lines >= 0 and file_lines < state.last_line_read:
                    print(f"Trace file on {pod_name} has {file_lines} lines but last_line_read={state.last_line_read} — nodeplugin likely restarted, resetting")
                    state.last_line_read = 0
                    state.leftover_line = None

            skip = state.last_line_read + 1
            if state.last_line_read == 0:
                read_cmd = f"cat /tmp/cvmfs-trace-{repo}.log"
            else:
                read_cmd = f"tail -n +{skip} /tmp/cvmfs-trace-{repo}.log"
            cmd = (
                f"kubectl exec -n {NAMESPACE} {pod_name} -c automount -- "
                f"{read_cmd}"
            )
            result = subprocess.run(
                cmd, shell=True, check=True,
                capture_output=True, text=True, timeout=30
            )
            if not result.stdout.strip():
                return []
            lines = result.stdout.strip().split('\n')
            state.last_line_read += len(lines)
            print(f"Read {len(lines)} new lines from {pod_name} (total tracked: {state.last_line_read})")
            return lines
        except subprocess.CalledProcessError as e:
            print(f"Failed to get trace file for {repo} on {pod_name}: {e}")
        except subprocess.TimeoutExpired:
            print(f"Read timed out for {repo} on {pod_name}")
        return []

    # ── parsing ──────────────────────────────────────────────────────

    def parse_new_lines(self, lines, pod_name):
        """Parse new trace lines for module opens.

        Handles cross-read boundary: if the last line of a read is an open()
        without its paired lookup(), it's saved and prepended to the next read.
        """
        state = self.pod_states.get(pod_name)
        if not state:
            return

        if state.leftover_line:
            lines = [state.leftover_line] + lines
            state.leftover_line = None

        new_opens = defaultdict(int)
        i = 0

        while i < len(lines):
            try:
                line = lines[i].strip()
                if not line or '"Tracer","flushed ring buffer"' in line:
                    i += 1
                    continue

                current = list(csv.reader([line]))[0]
                if len(current) < 4:
                    i += 1
                    continue

                if (current[1] == "1"
                        and "/containers/" in current[2]
                        and current[3] == "open()"):

                    # need the next line to confirm the pair
                    if i + 1 >= len(lines):
                        # last line — save for next read
                        state.leftover_line = lines[i]
                        break

                    next_stripped = lines[i + 1].strip()
                    if (next_stripped
                            and '"Tracer","flushed ring buffer"' not in next_stripped):
                        next_fields = list(csv.reader([next_stripped]))[0]
                        if (len(next_fields) >= 4
                                and next_fields[1] == "4"
                                and "/containers/" in next_fields[2]
                                and next_fields[3] == "lookup()"
                                and next_fields[2].endswith("/singularity")):
                            module_match = re.search(
                                r'/containers/([^/]+)/', current[2]
                            )
                            if module_match:
                                module = module_match.group(1)
                                new_opens[module] += 1
                            i += 2
                            continue

                i += 1

            except (csv.Error, IndexError) as e:
                print(f"Error parsing line {i} on {pod_name}: {e}")
                i += 1

        for module, count in new_opens.items():
            self.module_counts[module] += count
            print(f"Module {module}: +{count} opens from {pod_name} (cluster total: {self.module_counts[module]})")

    # ── main process cycle (called only when idle) ───────────────────

    def process_pod_when_idle(self, pod_name, repo):
        """Flush buffer, read new lines, parse, and clean up for one pod.

        Returns True if data was successfully read (even if empty after flush),
        False if flush or read failed.
        """
        if not self.flush_cvmfs_buffer(pod_name, repo):
            return False

        time.sleep(2)  # brief pause for flush to finish writing

        lines = self.get_new_trace_lines(pod_name, repo)
        if lines:
            self.parse_new_lines(lines, pod_name)

        state = self.pod_states.get(pod_name)
        if state and state.last_line_read > MAX_TRACE_LINES:
            print(f"Trace file on {pod_name} reached {state.last_line_read} lines, wiping...")
            self.wipe_trace_file(pod_name, repo)

        return True

    def get_prometheus_metrics(self):
        metrics = []
        metrics.append("# HELP cvmfs_module_opens_total Total number of module opens across cluster")
        metrics.append("# TYPE cvmfs_module_opens_total counter")
        for module, count in self.module_counts.items():
            metrics.append(f'cvmfs_module_opens_total{{module="{module}"}} {count}')
        return '\n'.join(metrics)


class MetricsServer:
    def __init__(self, parser):
        self.parser = parser

    def get_telegraf_metrics(self):
        try:
            response = requests.get("http://localhost:9001/metrics", timeout=5)
            if response.status_code == 200:
                return response.text
            return ""
        except Exception as e:
            print(f"Error fetching telegraf metrics: {e}")
            return ""

    def start_server(self):
        class MetricsHandler(BaseHTTPRequestHandler):
            def do_GET(handler_self):
                if handler_self.path == '/metrics':
                    metrics = []
                    trace_metrics = handler_self.server.parser.get_prometheus_metrics()
                    if trace_metrics:
                        metrics.append(trace_metrics)
                    telegraf_metrics = handler_self.server.metrics_server.get_telegraf_metrics()
                    if telegraf_metrics:
                        metrics.append(telegraf_metrics)
                    response = '\n'.join(metrics)
                    handler_self.send_response(200)
                    handler_self.send_header('Content-Type', 'text/plain')
                    handler_self.end_headers()
                    handler_self.wfile.write(response.encode())
                else:
                    handler_self.send_response(404)
                    handler_self.end_headers()

            def log_message(self, format, *args):
                pass

        server = HTTPServer(('0.0.0.0', 9002), MetricsHandler)
        server.parser = self.parser
        server.metrics_server = self
        print("Combined metrics server started on port 9002")
        server.serve_forever()


def main():
    parser = TraceParser()
    metrics_server = MetricsServer(parser)

    server_thread = threading.Thread(target=metrics_server.start_server, daemon=True)
    server_thread.start()

    print("Waiting for telegraf to start...")
    time.sleep(10)

    repos = ["neurodesk.ardc.edu.au"]

    # Wipe trace files on startup to avoid re-processing stale data
    initial_pods = parser.get_all_nodeplugin_pods()
    for pod in initial_pods:
        for repo in repos:
            print(f"Startup: wiping trace file for {repo} on {pod}...")
            parser.wipe_trace_file(pod, repo)

    while True:
        # Refresh pod list each cycle (pods can come and go)
        all_pods = parser.get_all_nodeplugin_pods()

        if not all_pods:
            print("Warning: No nodeplugin pods found, retrying...")
            time.sleep(POLL_INTERVAL)
            continue

        if parser.is_cvmfs_idle() and parser.pending_flush:
            print(f"CVMFS idle with pending activity — processing all pods...")
            all_succeeded = True
            for pod_name in all_pods:
                for repo in repos:
                    try:
                        if not parser.process_pod_when_idle(pod_name, repo):
                            all_succeeded = False
                    except Exception as e:
                        print(f"Error processing {repo} on {pod_name}: {e}")
                        all_succeeded = False
            if all_succeeded:
                parser.pending_flush = False
                parser.idle_count = 0
            else:
                print("Some pods failed, will retry next idle cycle")
        elif not parser.pending_flush:
            print("No new activity across cluster")
        else:
            print("CVMFS active, skipping all pods")

        print(f"Sleeping {POLL_INTERVAL}s...")
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
