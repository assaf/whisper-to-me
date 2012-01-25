/* The main rule parses a function or series list
 */
target
  = function / series


/* Parses into an object with the property function (function name) and arguments.  An argument may be a function,
 * series, string or number.
 */
function
  = name:[a-zA-Z]+ "(" args:arguments? ")" {
    return {
      function: name.join(""),
      args:     args
    }
    return name.join("")
  }

arguments
  = head:( argument "," " "* )* tail:argument {
    return head.map(function(arg) { return arg[0] }).concat(tail)
  }

argument
  = boolean / number / string / function / series


/* Parses into an object with the property series, which contains the FQN.  Will parse glob patterns as well.
 */
series
  = head:(name ".")* tail:name {
    var names = head.map(function(part) { return part[0] }).concat(tail);
    return { series: names.join(".") }
  }

name
  = glob / full:[a-zA-Z0-9_\-\[\]]* star:"*"? {
    full = full.join("")
    if (star)
      return full + star;
    return full.length > 0 ? full : null;
  }

glob
  = '{' match:[^}]* '}' {
    return '{' + match.join("") + '}'
  }


/* Parses into an object with the property string.
 */
string
  = '"' value:[^"]* '"' {
    return { string: value.join("") }
  }
   

/* Parses into an object with the property number.
 */
number
  = sign:[-+]? integer:[0-9]+ "."? fraction:[0-9]* {
    return { number: parseFloat(sign + integer.join("") + "." + fraction.join("")) }
  }

/* Parses into an object with the property boolean.
 */
boolean
  = value:("true" / "false") {
    return { boolean: value == 'true' }
  }