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

index=0
for f in `grep "http://pengzhangdev.tk" $new_post -rnH `
do
    index=$(($index+1))
    png=`echo $f |  cut -d \( -f 2 | cut -d \) -f 1 `
    destname=`basename $png | cut -d = -f 2`
    echo "downloand $png to assets/blog-images/$destname"
    wget $png -O assets/blog-images/$destname
done

sed -i "s/http:\/\/pengzhangdev.tk:31119\/api\/file\/getImage?fileId=/\/assets\/blog-images\//g" $new_post

