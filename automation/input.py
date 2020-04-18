import termios
import contextlib
import io
import os
import sys
import warnings


def multi_input(stream=None, input=None):
    # This doesn't save the string in the GNU readline history.
    if not stream:
        stream = sys.stderr
    if not input:
        input = sys.stdin

    # NOTE: The Python C API calls flockfile() (and unlock) during readline.
    contents = []
    while True:
        line = input.readline()
        if len(line) == 0:
            # EOF
            break
        contents.append(line)

    line = '\n'.join(contents)
    if not line:
        raise EOFError
    if line[-1] == '\n':
        line = line[:-1]
    return line


def hidden_multi_input(stream=None):
    """
    Gets multi-line input, hiding the input (useful for long pastes).
    Enter, then Control+D to finish
    """

    hidden_input = None
    with contextlib.ExitStack() as stack:
        try:
            # Always try reading and writing directly on the tty first.
            fd = os.open('/dev/tty', os.O_RDWR | os.O_NOCTTY)
            tty = io.FileIO(fd, 'w+')
            stack.enter_context(tty)
            input = io.TextIOWrapper(tty)
            stack.enter_context(input)
            if not stream:
                stream = input
        except OSError:
            # If that fails, see if stdin can be controlled.
            stack.close()
            try:
                fd = sys.stdin.fileno()
            except (AttributeError, ValueError):
                fd = None
                hidden_input = None
            input = sys.stdin
            if not stream:
                stream = sys.stderr

        if fd is not None:
            try:
                old = termios.tcgetattr(fd)     # a copy to save
                new = old[:]
                new[3] &= ~termios.ECHO  # 3 == 'lflags'
                tcsetattr_flags = termios.TCSAFLUSH
                try:
                    termios.tcsetattr(fd, tcsetattr_flags, new)
                    hidden_input = multi_input(stream, input=input)
                finally:
                    termios.tcsetattr(fd, tcsetattr_flags, old)
                    stream.flush()  # issue7208
            except termios.error:
                if hidden_input is not None:
                    raise
                if stream is not input:
                    # clean up unused file objects before blocking
                    stack.close()
                hidden_input = None

        stream.write('\n')
        return hidden_input
