"""Print the most frequent words in a text file, minus a stopword list."""

import collections
import pathlib
import re
import sys

WORD = re.compile(r"[a-z']+")


def load_stopwords(path):
    text = pathlib.Path(path).read_text(encoding="utf-8")
    return {line.strip() for line in text.splitlines() if line.strip()}


def count_words(text, stopwords):
    counts = collections.Counter()
    for word in WORD.findall(text.lower()):
        if word not in stopwords:
            counts[word] += 1
    return counts


def main(argv):
    if len(argv) < 2:
        print("usage: wordfreq.py FILE [TOP]", file=sys.stderr)
        return 2
    top = int(argv[2]) if len(argv) > 2 else 10
    stopwords = load_stopwords(pathlib.Path(__file__).with_name("stopwords.txt"))
    text = pathlib.Path(argv[1]).read_text(encoding="utf-8")
    for word, n in count_words(text, stopwords).most_common(top):
        print("%6d  %s" % (n, word))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
