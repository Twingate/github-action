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


# Development

To run action locally to debug you can use `act` (`brew install act`):
```
act -j test -s SERVICE_KEY --container-options "--cap-add NET_ADMIN --device /dev/net/tun"
```

It'll ask for `SERVICE_KEY` value interactively.

# How To Release

When releasing a new tag (`v1.4` for example) we also have to update the latest major version (`v1` in this case)
to point to it.
Example steps:

```
git tag v1.4
git tag v1 -f
git push origin v1 v1.4 -f
gh release create v1.4 --generate-notes --verify-tag
```