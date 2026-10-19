# Security policy

## Reporting a vulnerability

Please report a suspected vulnerability privately, through GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on the affected repository. Do not open a public issue for it.

Include: what an attacker can do, what they need in order to do it, and
the smallest reproduction you have. A protocol-level issue is often a
statement about a peer that behaves badly, so the peer's behaviour matters
as much as the victim's.

## What is in scope

The protocol's security properties are its own, and they are worth stating
because an implementation inherits them:

- **A peer is authenticated by the deployment, not by the protocol.** MLP
  carries no identity of its own. A deployment that puts an unauthenticated
  peer on a lane has made a deployment's mistake, and the protocol's
  objects will carry whatever that peer sends.
- **The protocol is not confidential.** Its objects are readable by anyone
  on the path. Confidentiality and integrity are the deployment's to
  provide, and a deployment that needs them MUST provide them — a
  transport that assumes the link is trustworthy is a transport that
  carries an attacker's content into a receiver's surface.
- **A peer that misbehaves is contained by the protocol, not trusted.** The
  bounded tables (§4.4), the caps (§3.2, §6.2), the deadlines (§8) and
  the validation order (§4.2) exist so that a hostile or broken peer
  cannot make a receiver allocate without bound, apply an object it did
  not validate, or hold a key forever.
- **A peer can make the link slow.** The estimator will discover a slow
  link and adapt to it; a peer cannot make the receiver believe the link is
  faster than it is, because the receiver measures the round-trip time
  itself.

## What is out of scope

- The content an update carries. That is a codec's business, and a codec
  has its own security properties.
- The deployment's authentication, authorization, key management, and
  network configuration.
- Denial of service by a peer that a deployment has already authorized to
  connect and that simply sends a lot: the protocol bounds what a peer can
  make the receiver *hold*, not how much bandwidth it may consume.

## Supported versions

Only the current version of the protocol is supported. A deployment that
must interoperate with an older one is carrying a second implementation
of the protocol, which this protocol does not permit (§12.1).
