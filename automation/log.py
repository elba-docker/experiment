import logzero
import textwrap
import os
from logzero import logger as log
from logzero.colors import Fore as ForegroundColors


class LogFormatter(logzero.LogFormatter):
    def __init__(self, colors=True, indent=True):
        if colors:
            fmt = '%(color)s%(inner)s%(end_color)s %(message)s'
        else:
            fmt = '%(inner)s %(message)s'
        inner = '[%(levelname)5s %(asctime)s %(module)s: %(lineno)4d]'
        datefmt = '%H:%M:%S'
        logzero.LogFormatter.__init__(self, fmt=fmt, datefmt=datefmt)
        self._inner = inner
        self._indent = indent

    def format(self, record):
        try:
            message = record.getMessage()
            record.message = message
        except Exception as e:
            record.message = "Bad message (%r): %r" % (e, record.__dict__)

        record.asctime = self.formatTime(record, self.datefmt)

        if record.levelno in self._colors:
            record.color = self._colors[record.levelno]
            record.end_color = self._normal
        else:
            record.color = record.end_color = ''

        record.levelname = custom_levelname(record.levelname)
        record.inner = self._inner % record.__dict__
        # Remove all blank-only lines
        lines = [line for line in record.message.splitlines() if len(line.strip()) > 0]

        if self._indent:
            inner_indent = len(record.inner) + 1
            indent = " " * inner_indent
            new_lines = []
            effective_width = int(columns) - inner_indent
            for i in range(len(lines)):
                line = None
                if len(lines[i]) > effective_width:
                    line = textwrap.wrap(lines[i], effective_width)
                else:
                    line = [lines[i]]
                for j in range(len(line)):
                    if i != 0 or j != 0:
                        new_lines.append(indent + line[j])
                    else:
                        new_lines.append(line[j])
            lines = new_lines

        record.message = "\n".join(lines)
        formatted = self._fmt % record.__dict__

        if record.exc_info:
            if not record.exc_text:
                record.exc_text = self.formatException(record.exc_info)
        if record.exc_text:
            lines = [formatted.rstrip()]
            lines.extend(
                str(ln) for ln in record.exc_text.split('\n'))
            formatted = '\n'.join(lines)
        return formatted


def custom_levelname(name):
    if name == "DEBUG" or name == "ERROR":
        return name
    else:
        return name[:4]


def setup_logger(colors=True, indent=True, **kwargs):
    return logzero.setup_logger(formatter=LogFormatter(colors=colors, indent=indent), **kwargs)


_, columns = os.popen('stty size', 'r').read().split()
logzero.formatter(LogFormatter())
log = log

