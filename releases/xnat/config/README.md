# xnat-web/config/README.md

XNAT configuration templates to merge configuration with secrets presented via environment variables.

All files in this directory will be copied into `/data/xnat/home/config` folder and passed via the
[envsubst](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html) command.
