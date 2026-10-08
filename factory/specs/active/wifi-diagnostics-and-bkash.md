# Wi-Fi latency diagnostics and bKash optimization

## Objective

Measure the real Wi-Fi path and preserve battery-efficient operation. Add a
bounded, manual diagnostic to LightFlow and the installed official bKash package
to the existing targeted ART action. Publish the tested module and evidence.

## Evidence

RMX3741 has a 5 GHz Wi-Fi link with approximately -59 dBm signal. Kernel power
saving is enabled, verbose Wi-Fi logging is disabled, and framework scan
throttling is enabled. Twenty-reply public probes have no loss: Cloudflare median
16.55 ms, Google DNS median 39.45 ms. Router returned 20 of 21 probes; that single
missing ICMP reply does not establish link loss. HTTPS requests succeed and
Android cached DNS resolution is about 3–7 ms. AOSP low-latency mode disables
Wi-Fi power saving, so forcing it conflicts with the battery requirement.

## Requirements

- No invented speed gain, DNS/MTU/TCP changes, disabled power saving, Wi-Fi lock,
  periodic network probe, scanning request, or resident optimizer.
- Use trusted Android utilities in the installed root diagnostic.
- Status mode sends no probe packets. Probe mode is manual, bounded and clearly
  labels router versus internet latency. Protect SSID, MAC and private addresses.
- Resolve an actual IPv4 Wi-Fi route rather than assuming a router address.
  Disconnected and IPv6-only cases skip IPv4 probes; reject malformed routes.
- Add only com.bKash.customerapp to targeted ART compilation and reporting.
  Preserve existing heat guards, profile use and native scheduling.
- Verify scripts, module ZIP, on-device behavior and restoration backup. Review
  diff before publishing. Keep raw diagnostics local and ignored.

## Completion

Installed module matches tested source. Publish to existing GitHub repository.
Report measurements and unchanged radio policy separately from unmeasured
battery/speed outcomes. No need to rerun all existing apps' compilation.
