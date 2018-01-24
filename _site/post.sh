#! /bin/bash

echo "Enter you post title"
read title
echo ""
echo "Enter the category name: "
echo "* 技术"
read category
echo ""

filename=`date +%Y-%m-%d`-`echo $title | sed 's/[ ][ ]*/-/g'`
new_post=_posts/${filename}.md

if [ -f $new_post ]; then
    echo "File $new_post already exists."
    exit 1
fi

echo "Creating new post $new_post"
echo -e "---\nlayout: default\ntitle: $title\ncategory: $category\ncomments: false\n---\n" > $new_post
echo "Enter the contents below, finish with Ctrl+D"
cat >> $new_post
sed -i "s/leanote:\/\/file\//http:\/\/pengzhangdev.tk:31119\/api\/file\//g" $new_post


