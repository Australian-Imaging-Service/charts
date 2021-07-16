---
title: "Recommendations"
weight: 10
---

# Operational recommendations

## Requirements and rationals

* Collaboration and knowledge share

  Tool selection has been chosen with a security oriented focus but enabling collaboration and sharing of site specific configurations, experiences and recommendations.

* Security

  A layered security approach with mechanisms to provide access at granular levels either through Access Control Lists (ACLs) or encryption

* Automated deployment
  * Allow use of Continuous Delivery (CD) pipelines
  * Incorporate automated testing principals, such as Canary deployments
* Federation of service

## Tools

* Git - version control
* [GnuPG](https://gnupg.org/) - Encryption key management
  * This can be replaced with a corporate Key Management Service (KMS) if your organisation supports this type of service.
* [Secrets OPerationS (SOPS)](https://github.com/mozilla/sops)
  * Encryption of secrets to allow configuration to be securly placed in version control.
  * SOPS allows full file encryption much like many other tools, however, individual values within certain files can be selectivly encrypted. This allows the majority of the file that does not pose a site specific security risk to be available for review and sharing amongst Federated support teams. This should also comply with most security team requirements (please ensure this is the case)
  * Can utilise GnuPG keys for encryption but also has the ability to incorporate more Corporate type Key Management Services (KMS) and role based groups (such as AWS AIM accounts)
* [git-secrets](https://github.com/awslabs/git-secrets)
  * Git enhancement that utilises pattern matching to help prevent sensitive information being submitted to version control by accident.
  * NB: Does not replace diligence but can help safe guard against mistakes.
