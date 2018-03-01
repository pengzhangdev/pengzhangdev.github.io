deploy:
	git checkout source
	jekyll build -p ./_plugins/
	git add -A
	git commit -m "update source"
	cp -r _site/ /tmp/
	git checkout master
	rm -r ./*
	cp -r /tmp/_site/* ./
	git add -A
	git commit -m "deploy blog"
	git push origin master
	git push coding master
	git checkout source
	echo "deploy succeed !"
	git push origin source
	git push coding source
	echo "push source !"
	rm -rf /tmp/_site/
