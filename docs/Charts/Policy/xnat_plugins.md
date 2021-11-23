---
title: "XNAT Plugin Policies"
linktitle: "Policy - plugins"
weight: 10
draft: true
---

## Supported plugin inclusion

An outline of considerations to be addressed for the inclusion of plugins to be supported within the AIS
production deployments. This is the first tier of plugins and will form part of the base images and be
incorporated as part of the developed orchestration and management plan.

1. Only [XNAT supported plugins](https://marketplace.xnat.org/plugins/) will be considered for inclusion
   into the base AIS XNAT image.
2. At least half of the AIS supported deployments of XNAT should have the intention of introducing the plugin
   into production within a 12 month period.
3. The plugin source code should demonstrate active support and assessment should conclude that future
   support is likely.
4. The plugin support during the AIS service should include resourcing, appropriate 'unit test' and any other
   applicable testing to ensure functionality and quality of service. This would include any long term overheads
   associated with the plugin inclusion.
5. Any complexity with the configuration of a plugin should, as is possible, be mitigated with the inclusion of
   appropriate default values, automated integration to other AIS services. This is to ensure that the base AIS product
   continues to uphold core requirements and reduce running overheads to each deployment site.

## Plugin retirement

A set of guidelines in the event that a previously supported plugin, through being superseded, dropping out of
support, no longer being utilised at a majority of AIS platforms, or other reasons that after careful consideration
the project deems as appropriate.

1. The intent to remove the plugin from core AIS deployment is to be notified to the AIS service areas for a
   period of 12 months using the current AIS notification mechanisms.
2. The plugin, if appropriate, will be moved to a lower tier inclusion in the AIS service. This may include
   addition of Kustomize templates and image build instructions to help support and advise sites as a best effort.
