# Twingate Connect Action
A GitHub action for connecting to Twingate

# Purpose
This action is used to connect your Github workflows to private resources using Twingate [Services](https://docs.twingate.com/docs/services). Services in Twingate allow applying zero trust permissions to automated components of your network infrastructure. For more information, see our [product announcement](https://www.twingate.com/blog/ztna-infra-automation/).

There are two common use cases:
1. Enabling access directly to private resources (eg. a database within a public cloud VPC) directly from your workflows without providing network-wide access. This allowed you to implement narrow, revocable access controls on any workflow. 
2. Enable running GitHub workflows on public runners while having IP restrictions enabled. Supporting this requires routing traffic to `github.com` via a Twingate Connector. More information on how to use Twingate with IP whitelisting is available in our [documentation](https://docs.twingate.com/docs/saas-app-gating).

# Usage
```yaml
- uses: twingate/github-action@v1
  with:
    # The Twingate Service Key used to connect Twingate to the proper service
    # Learn more about [Twingate Services](https://docs.twingate.com/docs/services)
    #
    # Required
    service-key: ${{ secrets.EXAMPLE_SERVICE_KEY_SECRET_NAME }}
```
