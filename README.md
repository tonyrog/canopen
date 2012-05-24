canopen
=====

canopen implements a CANopen stack.<br/>
See [www.can-cia.org](http://www.can-cia.org/index.php?id=canopen) for a description of CANopen.

### Dependencies

To build canopen you will need a working installation of Erlang R15B (or
later).<br/>
Information on building and installing [Erlang/OTP](http://www.erlang.org)
can be found [here](https://github.com/erlang/otp/wiki/Installation)
([more info](https://github.com/erlang/otp/blob/master/INSTALL.md)).

canopen is built using rebar that can be found [here](https://github.com/basho/rebar), with building instructions [here](https://github.com/basho/rebar/wiki/Building-rebar).

canopen also requires the following applications to be installed:
<ul>
<li>sl - https://github.com/tonyrog/sl</li>
<li>eapi - https://github.com/tonyrog/eapi</li>
<li>can - https://github.com/tonyrog/can</li>
</ul>


### Downloading

Clone the repository in a suitable location:

```sh
$ git clone git://github.com/tonyrog/canopen.git
```
### Configurating
#### Concepts

canopen can be started with a number of options.<br/>
For details either check [co_api.erl - start_link()](https://github.com/tonyrog/canopen/raw/master/src/co_api.erl) or in the full implementation documentation, see below on how to create it.

#### Files

Arguments to all applicable erlang applications are specified in an erlang configuration file.<br/>
An example can be found in ["sys.config"](https://github.com/tonyrog/canopen/raw/master/sys.config).<br/>


### Building

Rebar will compile all needed dependencies.<br/>
Compile:

```sh
$ cd canopen
$ rebar compile
...
==> canopen (compile)
```

### Running

There is a quick way to run the application for testing:

```sh
$ erl -config sys -pa <path>/canopen/ebin
>canopen:start().
```
(Instead of specifing the path to the ebin directory you can set the environment ERL_LIBS.)

Stop:

```sh
>halt().
```

### Release

To generate a proper release follow the instructions in [Release Handling](https://github.com/basho/rebar/wiki/Release-handling) or look in the [Rebar tutorial](http://www.metabrew.com/article/erlang-rebar-tutorial-generating-releases-upgrades).

<b>Before</b> the last step you have to update the file "canopen/rel/files/sys.config" with your own settings.
You probably also have to update "canopen/rel/reltool.config" with the correct path to your application (normally "{lib_dirs, ["../.."]}") and all apps you need.
```
       {app, sasl,   [{incl_cond, include}]},
       {app, stdlib, [{incl_cond, include}]},
       {app, kernel, [{incl_cond, include}]},
       {app, sl, [{incl_cond, include}]},
       {app, eapi, [{incl_cond, include}]},
       {app, can, [{incl_cond, include}]},
       {app, canopen, [{incl_cond, include}]}
```


And then you run: 
```
$ rebar generate
```
.

When generating a new release the old has to be (re)moved.

Start node:

```sh
$ cd rel
$ canopen/bin/canopen start
```

(If you want to have access to the erlang node use 
``` 
console 
```
instead of 
``` 
start
```
.)

### Documentation

canopen is documented using edoc. To generate the documentation do:

```sh
$ cd canopen
$ rebar doc
```


