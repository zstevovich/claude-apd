package tools

import (
	"reflect"
	"strings"
	"testing"
)

func paths(ts []Target) []string {
	var out []string
	for _, t := range ts {
		if t.Unknown != "" {
			out = append(out, "?")
			continue
		}
		out = append(out, t.Path)
	}
	return out
}

func TestWrites(t *testing.T) {
	cases := []struct {
		line string
		want []string // nil = the tool writes no file by itself in this form
		ok   bool
	}{
		{"cp a b", []string{"b"}, true},
		{"cp -r a b c dest/", []string{"dest/"}, true},
		{"cp -t dest a b", []string{"dest"}, true},
		{"cp --target-directory=dest a b", []string{"dest"}, true},
		{"install -m 755 a /usr/local/bin/a", []string{"/usr/local/bin/a"}, true},
		{"mv a b", []string{"a", "b"}, true},
		{"mv -t dest a b", []string{"a", "b", "dest"}, true},
		{"mkdir -p -m 700 a/b c", []string{"a/b", "c"}, true},
		{"touch -r ref a b", []string{"a", "b"}, true},
		{"rm -rf -- -weird a", []string{"-weird", "a"}, true},
		{"tee -a log.txt other.txt", []string{"log.txt", "other.txt"}, true},
		{"chmod 644 a b", []string{"a", "b"}, true},
		{"chown user:grp a", []string{"a"}, true},
		{"truncate -s 0 a", []string{"a"}, true},
		{"rsync -a --exclude x src/ dest/", []string{"dest/"}, true},
		{"ln -s ../target link", []string{"link"}, true},
		{"ln -s /etc/passwd", []string{"passwd"}, true},
		{"dd if=/dev/zero of=disk.img bs=1m", []string{"disk.img"}, true},
		{"curl -o out.bin https://x", []string{"out.bin"}, true},
		{"curl -sS https://x", nil, true},
		{"curl -sSLo out.bin https://x", []string{"out.bin"}, true},
		{"curl -sSLoout.bin https://x", []string{"out.bin"}, true},
		{"curl -H o -d o https://x", nil, true},
		{"curl -fsSLO https://x/y", []string{"./"}, true},
		{"curl -O --output-dir dl https://x/y", []string{"dl"}, true},
		{"curl --output-dir dl -o x https://x/y", []string{"dl/x"}, true},
		{"curl --output-dir dl -o /abs/x https://x/y", []string{"/abs/x"}, true},
		{"curl -K cfg https://x/y", []string{"?"}, true},
		{"curl -s -w %output{f}%{http_code} https://x/y", []string{"?"}, true},
		{"curl -s -w %{http_code} https://x/y", nil, true},
		{"wget --warc-file=w -O- https://x/y", []string{"w.warc.gz", "w.warc"}, true},
		{"wget --rejected-log=r.log -O- https://x/y", []string{"r.log"}, true},
		{"tar --delete -f a.tar member", []string{"a.tar"}, true},
		{"tar -Af a.tar b.tar", []string{"a.tar"}, true},
		{"wget -e output_document=x https://x/y", []string{"?", "./"}, true},
		{"rsync -a --backup-dir=bak -T /abs/tmp src/ dest/", []string{"dest/", "dest/bak", "/abs/tmp"}, true},
		{"rsync -a --backup-dir=~/bak src/ dest/", []string{"dest/", "dest/./~/bak"}, true},
		{"rsync -a --backup-dir ~/bak src/ dest/", []string{"dest/", "~/bak"}, true},
		{"rsync -a --backup-dir=bak src/f d/f", []string{"d/f", "d/f/bak", "d/bak"}, true},
		{"rsync -a --backup-dir=bak src/f f", []string{"f", "f/bak", "./bak"}, true},
		{"sort --output=~/x in", []string{"./~/x"}, true},
		{"curl --output-dir dl -o a https://x --next -o b https://y", []string{"?", "dl/a", "dl/b"}, true},
		{"rsync -a --link-dest ../prev src/ dest/", []string{"dest/"}, true},
		{"curl -sD headers.txt -c jar.txt https://x", []string{"headers.txt", "jar.txt"}, true},
		{"curl -o - https://x", nil, true},
		{"wget -qO out https://x/y", []string{"out"}, true},
		{"wget -qO- https://x/y", nil, true},
		{"wget -P dl https://x/y", []string{"dl"}, true},
		{"wget -o log.txt https://x/y", []string{"log.txt", "./"}, true},
		{"sort -uo out in", []string{"out"}, true},
		{"sort -t , -k 2 in", nil, true},
		{"cp -rt dest a b", []string{"dest"}, true},
		{"cp -rtdest a b", []string{"dest"}, true},
		{"mv -vt dest a", []string{"a", "dest"}, true},
		{"ln -st dest target", []string{"dest"}, true},
		{"install -Dm755 a dest/a", []string{"dest/a"}, true},
		{"mkdir -pm 700 a", []string{"a"}, true},
		{"touch -cr ref a", []string{"a"}, true},
		{"truncate -cs 0 a", []string{"a"}, true},
		{"chmod --reference=ref a b", []string{"a", "b"}, true},
		{"rsync -a --log-file=l.txt src/ dest/", []string{"l.txt", "dest/"}, true},
		{"find src -fprint out.txt", []string{"out.txt"}, true},
		{"wget https://x/y", []string{"./"}, true},
		{"wget -O out https://x/y", []string{"out"}, true},
		{"sort -o out in", []string{"out"}, true},
		{"sort --output=out in", []string{"out"}, true},

		{"tar xf a.tar", []string{"./"}, true},
		{"tar xzf a.tgz -C dest", []string{"dest"}, true},
		{"tar -xf a.tar -C dest", []string{"dest"}, true},
		{"tar --extract --file a.tar --directory=dest", []string{"dest"}, true},
		{"tar tf box.tar -C /etc", nil, false},
		{"tar czf box.tar.xz src", []string{"box.tar.xz"}, true},
		{"tar -czf out.tgz -C src .", []string{"out.tgz"}, true},
		{"tar xzC dest -f a.tgz", []string{"dest"}, true},
		{"tar -xzC dest -f a.tgz", []string{"dest"}, true},
		{"tar xfC a.tar dest", []string{"dest"}, true},
		{"tar -tzf a.tgz", nil, false},
		{"tar cf - src", nil, false},
		{"unzip a.zip -d dest", []string{"dest"}, true},
		{"unzip -oq a.zip", []string{"./"}, true},
		{"unzip -l a.zip", nil, false},

		{"sed -i s/a/b/ f", []string{"f"}, true},
		{"sed -i '' s/a/b/ f g", []string{"f", "g"}, true},
		{"sed -Ei -e s/a/b/ f", []string{"f"}, true},
		{"sed --in-place=.bak s/a/b/ f", []string{"f"}, true},
		{"sed -n s/a/b/p f", nil, false},
		{"perl -pi -e s/a/b/ f", []string{"f"}, true},
		{"perl -e print", nil, false},

		{"git rm -f a b", []string{"a", "b"}, true},
		{"git clean -fd", []string{"./"}, true},
		{"git checkout main -- a b", []string{"a", "b"}, true},
		{"git checkout main", nil, true},
		{"git status", nil, false},
		{"git diff --output=out.patch HEAD~1", []string{"out.patch"}, true},
		{"git diff HEAD~1", nil, false},
		{"git format-patch -o patches HEAD~3", []string{"patches"}, true},
		{"git format-patch HEAD~3", []string{"./"}, true},
		{"git format-patch --stdout HEAD~3", nil, false},
		{"git archive -o a.tar HEAD", []string{"a.tar"}, true},
		{"git bundle create b.bundle HEAD", []string{"b.bundle"}, true},
		{"git worktree add ../wt main", []string{"../wt"}, true},
		{"git init newrepo", []string{"newrepo"}, true},
		{"git clone --depth 1 https://x/y.git dest", []string{"dest"}, true},
		{"git clone https://x/y.git", []string{"./"}, true},
		{"git clone --separate-git-dir=/abs/g https://x/y.git d", []string{"/abs/g", "d"}, true},
		{"git diff --outp=o.patch", []string{"o.patch"}, true},
		{"git -C sub diff --output=o.patch", []string{"?"}, true},
		{"git -C sub status", nil, false},
		{"git --no-pager diff --output=o.patch", []string{"o.patch"}, true},
		{"git -c core.pager=cat rm a", []string{"a"}, true},
		{"cp --target-dir=dest a b", []string{"dest"}, true},
		{"sort --outp=o in", []string{"o"}, true},
		{"mkdir --mod=700 a", []string{"a"}, true},

		{"find src -name *.tmp -delete", []string{"src"}, true},
		{"find a b -exec rm {} ;", []string{"a", "b"}, true},
		{"find -exec cat {} ;", nil, false},
		{"find -type f -delete", []string{"./"}, true},

		{"cat a b", nil, false},
	}
	for _, c := range cases {
		f := strings.Fields(c.line)
		for i := range f {
			if f[i] == "''" {
				f[i] = ""
			}
		}
		ts, ok := Writes(f[0], f[1:])
		if ok != c.ok || !reflect.DeepEqual(paths(ts), c.want) {
			t.Errorf("%-45s got %v ok=%v, want %v ok=%v", c.line, paths(ts), ok, c.want, c.ok)
		}
	}
}

func TestNoFollow(t *testing.T) {
	for cmd, want := range map[string]bool{"rm": true, "rmdir": true, "unlink": true, "tee": false, "cp": false} {
		ts, _ := Writes(cmd, []string{"x", "y"})
		if len(ts) == 0 || ts[len(ts)-1].NoFollow != want {
			t.Errorf("%s: NoFollow want %v, got %+v", cmd, want, ts)
		}
	}
}
