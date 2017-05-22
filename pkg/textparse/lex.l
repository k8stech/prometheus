%{
// Copyright 2017 The Prometheus Authors
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package textparse

import (
        "fmt"
        "math"
        "strconv"

        "github.com/prometheus/prometheus/pkg/value"
)


// Lex is called by the parser generated by "go tool yacc" to obtain each
// token. The method is opened before the matching rules block and closed at
// the end of the file.
func (l *lexer) Lex() int {
    const (
        lstateInit = iota
        lstateValue
        lstateTimestamp
        lstateLabels
        lstateLName
        lstateLValue
    )
    s := lstateInit
    
    if l.i >= len(l.b) {
        return eof
    }
    c := l.b[l.i]

    l.ts = nil
    l.mstart = l.nextMstart
    l.offsets = l.offsets[:0]
%}

D     [0-9]
S     [a-zA-Z]
L     [a-zA-Z_]
M     [a-zA-Z_:]

%x lstateValue lstateTimestamp lstateLabels lstateLName lstateLValue


%yyc c
%yyn c = l.next()
%yyt s


%%

\0                                    return eof
#[^\r\n]*\n                           l.mstart = l.i
[\r\n \t]+                            l.mstart = l.i

{S}({M}|{D})*\{                       s = lstateLabels
                                      l.offsets = append(l.offsets, l.i-1)
{S}({M}|{D})*                         s = lstateValue
                                      l.mend = l.i
                                      l.offsets = append(l.offsets, l.i)

<lstateLabels>[ \t]+
<lstateLabels>,?\}                    s = lstateValue
                                      l.mend = l.i
<lstateLabels>,?                      s = lstateLName
                                      l.offsets = append(l.offsets, l.i)

<lstateLName>{S}({L}|{D})*=           s = lstateLValue
                                      l.offsets = append(l.offsets, l.i-1)

<lstateLValue>\"(\\.|[^\\"])*\"       s = lstateLabels
                                      l.offsets = append(l.offsets, l.i-1)
<lstateLValue>\'(\\.|[^\\'])*\'       s = lstateLabels
                                      l.offsets = append(l.offsets, l.i-1)

<lstateValue>[ \t]+                   l.vstart = l.i
<lstateValue>(NaN)                    l.val = math.Float64frombits(value.NormalNaN)
                                      s = lstateTimestamp

<lstateValue>[^\n \t\r]+              // We don't parse strictly correct floats as the conversion
                                      // repeats the effort anyway.
                                      l.val, l.err = strconv.ParseFloat(yoloString(l.b[l.vstart:l.i]), 64)
                                      if l.err != nil {
                                          return -1
                                      }
                                      s = lstateTimestamp

<lstateTimestamp>[ \t]+               l.tstart = l.i         
<lstateTimestamp>{D}+                 ts, err := strconv.ParseInt(yoloString(l.b[l.tstart:l.i]), 10, 64)
                                      if err != nil {
                                          l.err = err
                                          return -1
                                      }
                                      l.ts = &ts
<lstateTimestamp>[\r\n]+              l.nextMstart = l.i
                                      return 1
<lstateTimestamp>\0                   return 1              
   
%%
    l.err = fmt.Errorf("no token found")
    return -1
}