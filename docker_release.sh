#! /usr/bin/env bash

# create the control path for ssh
CONTROL_PATH=$(grep ControlPath /root/.ssh/config | awk '{ print $2 }' | xargs dirname)
mkdir -p ${CONTROL_PATH/#~/$HOME}

# use the most modern bundle available to allow OTP
gem install bundle
bundle update --bundler

bash
