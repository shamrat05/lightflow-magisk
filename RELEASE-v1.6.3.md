# LightFlow 1.6.3

Include Instagram in the optional profile optimization action. Previously it was omitted even when Android had only verification artifacts for it. LinkedIn, Reddit, YouTube, Facebook, and both WhatsApp packages remain covered.

Avoid starting compilation when Android reports moderate or worse thermal throttling, or when thermal status cannot be read. Battery temperature alone missed the phone's thermal throttling during scrolling. The status report now includes live thermal sensor readings and Instagram/LinkedIn compilation state.

Verified on RMX3741 that thermal status 2 defers the action before compilation. Android shell syntax and ZIP integrity checks passed. Instagram compilation is deferred until the phone is cool; no FPS improvement or battery saving is claimed. The existing agy launch policy is unchanged.
