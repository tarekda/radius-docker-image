#!/bin/bash

#echo $((86400 - $(date +%s) % 86400))
# Get the current time in seconds since midnight
current_time=$(date +%s)
# Get the current time in seconds since the beginning of the day
seconds_since_midnight=$(( current_time % 86400 ))
# Calculate remaining seconds until midnight
remaining_seconds=$(( 86400 - seconds_since_midnight ))
# Print the result
echo $remaining_seconds