# CERN Maps

This package lets agents use the public CERN Maps services (`maps.cern.ch`): find a building, room
or point of interest on the CERN sites, read its details, find a building by number, and work out a
route between two places with the distance and the travel time on foot, by bike or by car. The
services are public; there is no account or password to set up.

## Connect it

1. Approve the package (an instance administrator reviews it once: it can make `GET` requests to
   five specific paths on `maps.cern.ch`, listed in the approval).
2. On an agent's **Access** tab, choose **Give access** next to CERN Maps. There is nothing to
   enter: Aurora creates the workspace's connection for you the first time, and you can still see
   and revoke it under Connections.

## What it can and cannot do

- It only **reads**: the place search, the place details, the building geocoder, the routing
  travel modes and the route calculation. Every other path on the host stays blocked, whatever the
  agent asks for.
- Routes are calculated on CERN's own road and path network. Times are a guide, and each answer
  says for which mode (walking, cycling or driving) it was computed.
- Agents can also give you an "Open in CERN Maps" link; that is a plain link and needs no request.
- Every request goes through your rules and is written to the request log like any other.
