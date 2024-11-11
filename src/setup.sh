#!/bin/sh

WG_PROCESS_FOREGROUND=1 amneziawg-go wg0 &
node server.js
