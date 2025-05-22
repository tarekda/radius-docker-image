#!/bin/bash

# For example, set the Reply-Message attribute:
echo "Reply-Message := \"Test echo from FreeRADIUS exec module\""

# Possibly set a temporary attribute with the user's name:
echo "Tmp-String-0 := $USER_NAME"

exit 0
