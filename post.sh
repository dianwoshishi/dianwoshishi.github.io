#!/bin/bash
post_directory=./_posts 
all_files=$(ls -l $post_directory | grep '^-' | awk '{print $9}'  )
for file in $all_files
do
    # echo $file
    first_line=$(head -n 1 $post_directory/${file})
    # echo $first_line
    if [ -n "$first_line" ]
    then
        content=$(cat $post_directory/$file)
        echo $first_line
        if [ "$first_line"x != "---"x ]
        then
            echo $first_line
            echo '---' > $post_directory/${file}
            echo "title: ${first_line:1}" >> $post_directory/${file}
            echo '---' >> $post_directory/${file}
            # echo $content >> $post_directory/${file}
            for line in $content
            do
                    echo $line >> $post_directory/${file}
            done
        fi
    fi
done