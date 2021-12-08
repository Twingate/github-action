# Twingate Connect Action
A GitHub action for connecting to Twingate

# Purpose
This action is used to connect your Github workflows to Twingate. One use case for this is to enable running GitHub workflows on public runners while having IP restrictions enabled (your Twingate service must be routing `github.com`).

# Usage
```yaml
- uses: twingate/github-action@v1
  with:
    # The Twingate Service Key used to connect Twingate to the proper service
    # [Learn more about Twingate Services](https://docs.twingate.com/docs/services#service-creation-steps)
    #
    # Required
    service-key: ${{ secrets.EXAMPLE_SERVICE_KEY_SECRET_NAME }}
```
