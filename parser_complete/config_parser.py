"""
Script to parse basic bash config.sh file
"""

__author__ = "Joseph Azevedo"
__version__ = "1.0"

import re

# (Naive) regex for a single non-comment line from config.sh
line_regex = re.compile(r"^(?:readonly )?([A-Za-z_0-9-]+)=(.*)$")
quote_regex = re.compile(r'^"(.*)"$')


def main(iterator):
  """
  Given a line iterator of the bash file, returns a dictionary of
  keys to values
  """

  values = {}
  for line in iterator:
    if not line.startswith('#') and len(line.strip()) > 0:
      match_obj = line_regex.search(line)
      if match_obj is not None:
        key, value = match_obj.group(1), match_obj.group(2)
        values[key] = try_parse(value)

  return values


def try_parse(value):
  """
  Tries to parse a value, attempting to convert it to an int or
  float before falling back to a string
  """

  match_obj = quote_regex.search(value)
  if match_obj is not None:
    # Unwrap the value outside of quotes if applicable
    value = match_obj.group(1)

  try:
    if value.isdigit():
      value_as_int = int(value)
      return value_as_int
    else:
      value_as_float = float(value)
      return value_as_float
  except ValueError:
    return value