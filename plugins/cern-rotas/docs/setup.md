# CERN Rota

This package lets agents read one rota from CERN's Accelerator Schedule Management service
(ASM, `asm.cern.ch`): who is on duty now, and the assignments from today to a week ahead (on a
weekly rota, the current person and the next one). Agents can then answer "who is on the Linux
rota today?" or "when is my next rota week?". ASM publishes this without signing in; there is no
account, password or CERN single sign-on to set up.

**One connection is one rota.** To follow several rotas (Linux, Snow-flake, …), connect the app
once per rota and name each connection after its rota.

## Before you connect it (the operator of this Aurora installation)

`asm.cern.ch` is only reachable from inside CERN's network, and two gateway settings are needed:

1. **Allow the private address.** `asm.cern.ch` resolves to a private address (`172.18.x.x`),
   which the gateway refuses by default. Add the host name `asm.cern.ch` to
   `gateway.allowed_private` (Administration › Limits, or `config.gateway.allowed_private` in the
   Helm values). With network policies enabled, the gateway also needs an egress rule to that
   address on port 443 (`networkPolicy.gatewayExtraEgress`). Without this, requests fail with
   `destination_refused`.
2. **Trust CERN's Grid certificate authority.** ASM's server certificate is issued by the **CERN
   Grid Certification Authority**, and the server does not send that certificate with its own. Add
   it to the gateway's extra trust bundle (`tls.extra_ca_bundle`, Helm `extraCaBundle`), next to
   CERN Root Certification Authority 2 if you already trust it for CERN Phonebook. Download it from
   <https://cafiles.cern.ch/cafiles/certificates/CERN%20Grid%20Certification%20Authority(1).crt>
   (PEM) and check its SHA-256 fingerprint
   `74:F5:B6:02:80:7C:76:F5:65:1C:73:F7:8E:B7:44:2C:A2:AB:73:5D:CD:C1:D1:89:0D:38:6E:16:41:4B:51:FD`
   against CERN's CA page before trusting it.

## Find the team ID

Each rota is a team in ASM. The address of a team's planning page on <https://asm.cern.ch> carries
two numbers, its unit's ID and its own; enter the team's. For example, the Linux rota is team
`14651` in unit `2325`. Some IT rotas: Linux `14651`, Snow-flake (cloud) `14652`, CEPH `15249`,
EOS `13188`, CERNBox `12808`, FTS `15109`, CVMFS `26501157`.

## Connect it

1. Approve the package (an instance administrator reviews it once: it can make `GET` requests to
   three paths under `https://asm.cern.ch/api/teams/`, listed in the approval).
2. Connect **CERN Rota** and enter the **ASM team ID**. Aurora does not check it when you connect
   (the check would need the private address above). A wrong ID shows up as empty answers.
3. **Rename the connection** after the rota, for example "Linux rota" (the connection's menu,
   **Rename**). The agent sees that name and nothing else to tell your rotas apart.
4. Give the agent access to the connection, as for any other app.

## What it can and cannot do

- It only **reads** three things of the connection's team: who is on duty now (`on-duty`), the
  assignments from today to seven days ahead (`week-plan`) and the rota's role definitions
  (`roles`). The team in the address is always the connection's: an agent cannot read another
  team through it. Every other path on `asm.cern.ch` is blocked, whatever the agent asks for,
  including the team member list (it can carry private phone numbers) and the full planning.
- **Only the coming seven days.** The full planning on ASM needs CERN single sign-on, so "when is
  my next rota week?" is answered only if that week starts within the next seven days. Otherwise
  the agent says so and points to ASM.
- ASM's answers include each assignee's name, CERN login, e-mail, work phone and **any leave
  recorded for them in ASM** (for example "Absence Pending Authorization"). The agent receives
  them as ASM returns them.
- Every request goes through your rules and is written to the request log like any other.
