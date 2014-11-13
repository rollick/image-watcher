#!/bin/bash

# For Mac
#fswatch -0 -r -n -I -x <path to images> | xargs -0 -n1 -I{} ruby handler.rb -a {}

# For linux
inotifywait -rme move,create,delete -r --exclude "[\!|\.]sync" --format '%w%f' /var/www/sync | while read FILE
do
  ruby handler.rb -p $FILE
done
