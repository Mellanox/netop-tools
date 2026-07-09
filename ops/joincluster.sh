#!/bin/bash
#
#
#${KADMCL} join 7.7.1.10:6443 --token 9n3r0k.yotkcmgn9bg8mdwz --discovery-token-ca-cert-hash sha256:e9f35620a5366220ea2a38a616c4f0fbd2659c7ee71ad757d7b1b64904c4e18c
${KADMCL} token create --print-join-command
