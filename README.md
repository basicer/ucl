
```

                                    
                _|_|_|    _|        
  _|    _|    _|          _|        
  _|    _|    _|          _|        
  _|    _|    _|          _|        
    _|_|_|      _|_|_|    _|_|_|_|  
        _|                     
        _|_|  Micro Command Language


```

![Unit Tests](https://github.com/basicer/ucl/workflows/Unit%20Tests/badge.svg)

## Features:
* [Dodekalogue](https://wiki.tcl-lang.org/page/Dodekalogue) style syntax makes use at the command line just as easy as in the editor.

* Inspired by [fennel](https://fennel-lang.org/), µCL compiles to lua.  This enables JITed execution thanks to luajit, as well as the ability to integrate with pure lua environments such as [Roblox](https://roblox.com), [factorio](https://wiki.factorio.com/Modding), and [Gary's Mod](https://wiki.facepunch.com/gmod/Beginner_Tutorial_Intro). µCL can also be used in the browser via [fengari](https://fengari.io/).

* Packs to a single `.lua` file for easy inclusion in other projects.

* Inspired by [Forth](https://en.wikipedia.org/wiki/Forth_%28programming_language%29), command words can have both execution and completion semantics.  Execution semantics are further divided into pure (side-effect free) and non-pure.

## Installing
```
luajit pack.lua /usr/local/bin/ucl
chmod +x /usr/local/bin/ucl
ucl --test
```
This creates an amalgamated copy of ucl into a location normally include in $PATH, makes it execuatable, and runs the builtin self tests.
