# Shown when you open Unraid Docker → Console (interactive bash).
if [[ $- == *i* ]]; then
  echo
  echo "  Live Bedrock admin console:  mc-console"
  echo "  One-shot command:            mc-cmd say hello"
  echo "  Detach from console:         Ctrl-b then d  (server keeps running)"
  echo
fi
