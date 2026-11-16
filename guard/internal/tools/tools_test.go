package tools

import (
	"reflect"
	"strings"
	"testing"
)

func paths(ts []Target) []string {
	var out []string
	for _, t := range ts {
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
		{"wget https://x/y", []string{"./"}, true},
		{"wget -O out https://x/y", []string{"out"}, true},
		{"sort -o out in", []string{"out"}, true},
		{"sort --output=out in", []string{"out"}, true},

		{"tar xf a.tar", []string{"./"}, true},
		{"tar xzf a.tgz -C dest", []string{"dest"}, true},
		{"tar -xf a.tar -C dest", []string{"dest"}, true},
		{"tar --extract --file a.tar --directory=dest", []string{"dest"}, true},
		{"tar tf box.tar -C /etc", nil, false},
		{"tar czf box.tar.xz src", nil, false},
		{"unzip a.zip -d dest", []string{"dest"}, true},

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
