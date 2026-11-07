"""A git fast-import stream for the `big` fixture: 100,000 commits, ~8,000 merges,
~7,000 branches, 2,000 small files, plus huge.txt (200,000 lines) in the last commit.
Seeded, so every run produces the same history."""
import random
import sys

random.seed(42)
out = sys.stdout.buffer
COMMITS = 100_000
FILES = 2_000
MAX_BRANCHES = 7_000
mark = 0
time = 1_700_000_000
authors = [("Ada Lovelace", "ada@example.com"), ("Grace Hopper", "grace@example.com"),
           ("Alan Turing", "alan@example.com"), ("Demo Person", "demo@example.com")]


def write(s):
    out.write(s.encode() if isinstance(s, str) else s)


def data(payload):
    b = payload.encode() if isinstance(payload, str) else payload
    write(f"data {len(b)}\n")
    write(b)
    write("\n")


def commit(ref, message, parents, files):
    global mark, time
    mark += 1
    time += 37
    name, email = random.choice(authors)
    write(f"commit {ref}\nmark :{mark}\n")
    write(f"author {name} <{email}> {time} +0000\ncommitter {name} <{email}> {time} +0000\n")
    data(message)
    if parents:
        write(f"from :{parents[0]}\n")
        for p in parents[1:]:
            write(f"merge :{p}\n")
    for path, content in files:
        write(f"M 100644 inline {path}\n")
        data(content)
    return mark


main = commit("refs/heads/main", "Initial import", [], [(f"f{i}.txt", f"file {i}\n") for i in range(FILES)])
active = []
branches = 0
count = 1
while count < COMMITS - 1:
    r = random.random()
    n = count
    change = [(f"f{random.randrange(FILES)}.txt", f"change {n}\n")]
    if r < 0.085 and active:
        name, tip = active.pop(random.randrange(len(active)))
        main = commit("refs/heads/main", f"Merge branch '{name}'", [main, tip], change)
    elif r < 0.16 and branches < MAX_BRANCHES:
        branches += 1
        name = f"topic/b{branches:04}"
        tip = commit(f"refs/heads/{name}", f"Start {name}", [main], change)
        active.append((name, tip))
    elif r < 0.5 and active:
        i = random.randrange(len(active))
        name, tip = active[i]
        active[i] = (name, commit(f"refs/heads/{name}", f"Work on {name} ({n})", [tip], change))
    else:
        main = commit("refs/heads/main", f"Change {n} on main", [main], change)
    count += 1
huge = "".join(f"line {i:06} of a very long file\n" for i in range(200_000))
commit("refs/heads/main", "Add huge.txt", [main], [("huge.txt", huge)])
write("done\n")
