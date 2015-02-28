#!/bin/bash

# For Mac
#fswatch -0 -r -n -I -x <path to images> | xargs -0 -n1 -I{} ruby handler.rb -a {}

# For linux
inotifywait -rme move,create,delete,modify -r --exclude "\!sync|\.sync|resized|\.stfolder|\.stversions" --format "%w%f" /var/www/sync | while read FILE;  
do 
	echo $FILE && ruby run.rb -r /var/www/sync -p "$FILE";  
done
