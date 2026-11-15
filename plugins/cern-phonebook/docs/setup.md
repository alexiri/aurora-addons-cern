# CERN Phonebook

This package lets agents search CERN's central directory, `xldap.cern.ch`, for people and e-groups:
e-mail addresses, offices, departments and managers. It uses the directory's **anonymous read
access**; there is no account, password or CERN single sign-on to set up.

## Before you connect it: trust CERN's certificate authority

The directory's server certificate is issued by CERN's own certificate authority (**CERN Root
Certification Authority 2**), which is not in the public root stores. The gateway checks the
certificate and refuses the connection otherwise, so the operator of this Aurora installation must
add that root to the gateway's extra trust bundle (`tls.extra_ca_bundle`). Download it from
<https://cafiles.cern.ch/cafiles/certificates/CERN%20Root%20Certification%20Authority%202.crt>
(DER; convert to PEM with `openssl x509 -inform der`) and check its SHA-256 fingerprint
`18:7F:4F:7B:13:15:EB:D2:B7:25:47:C1:AC:CF:2E:C4:07:7D:51:C1:4A:0C:E5:74:90:4A:9F:DA:EA:8A:32:0C`
against CERN's CA page before trusting it. Without it, searches fail with `ldap_unavailable`.

## Connect it

1. Approve the package (an instance administrator reviews it once: it can read directory entries
   from `xldap.cern.ch:636` below `DC=cern,DC=ch`, for the attributes listed in the approval).
2. Add the connection (nothing to enter; give it a label such as "CERN directory") and grant it to
   the agents or workspaces that should be able to look people up.

## What it can and cannot do

- It performs **searches only**. The gateway talks to the directory over LDAPS with the server
  certificate verified; no write operation can be expressed.
- Only the listed attributes can be asked for or used in a filter. Contract status and nationality
  are not offered.
- A search returns at most 50 entries; every search goes through your rules and is written to the
  request log like any other request.

If CERN later requires signing in to read the directory, this package will need a new version with
its own review; it does not use CERN SSO today.
