#! /bin/bash

git add ./

git commit -m "update documents"

docker run --rm -it -p 8000:8000 -v ${PWD}:/docs squidfunk/mkdocs-material build

if [ -d /tmp/_site ]; then
    rm -rf /tmp/_site
fi

mv site /tmp_site

coding=`git remote show  | grep coding | wc -l`

if [ $coding -eq 0 ]; then
    git remote add coding git@git.coding.net:wertherzhang/wertherzhang.coding.me.git
fi

git push coding mkdocs
git push origin mkdocs

git checkout master

branch=`git branch | grep "*"`

if [[ $branch == *"master" ]]; then
    echo "On master"
else
    echo "Failed to switch to master and update size"
    exit
fi

git push coding master
git push origin master
