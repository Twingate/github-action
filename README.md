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

# Known Limitations

## Actions running docker steps that require access to a Twingate Resource

When running steps that run inside a docker container you'll need to override the container's `resolv.conf` 
by running the following inside the container:

```
echo "nameserver 100.95.0.251\nnameserver 100.95.0.252\nnameserver 100.95.0.253\nnameserver 100.95.0.254" > /etc/resolv.conf
```

### Technical details

The reason behind this is that on the VM running the Github workflow, Microsoft adds their own nameserver - `nameserver 168.63.129.16` - as part of internal logic to health Azure VMs (see details [here](https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16?tabs=windows)).

The VM ad logic to only use that nameserver to resolve an internal Azure DNS:
```
$> resolvectl status

Global
         Protocols: -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
  resolv.conf mode: stub

Link 2 (eth0)
    Current Scopes: DNS
         Protocols: +DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 168.63.129.16
       DNS Servers: 168.63.129.16
        DNS Domain: l2n2ciljpwpefjhhlkzs4uiluc.ex.internal.cloudapp.net

Link 3 (docker0)
    Current Scopes: none
         Protocols: -DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported

Link 4 (sdwan0)
    Current Scopes: DNS
         Protocols: +DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 100.95.0.251
       DNS Servers: 100.95.0.251 100.95.0.252 100.95.0.253 100.95.0.254
        DNS Domain: ~.
```

However, when running a docker container that address is also copied to its `resolv.conf` file but the logic on when to use it is lost.
Depending on the order of nameservers in `resolv.conf` - `168.63.129.16` might appear first and override the system's DNS preventing requests from reaching the Twingate Client.
The only workaround is to remove that nameserver from the container's `resolv.conf` file (it will never need it anyway as its not an Azure resource).
