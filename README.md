canopen
=====

canopen implements a CANOpen stack.<br/>
See www.canopensolutions.com for a description of CANOpen. 

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

...

#### Files

Arguments to all applicable erlang applications are specified in an erlang configuration file.<br/>
An example can be found in ["sys.config"](https://github.com/tonyrog/canopen/blob/master/sys.config).<br/>


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

To generate a proper release follow the instructions in 
https://github.com/basho/rebar/wiki/Release-handling.

You have to update the file "canopen/rel/files/sys.config" with your own settings <b> before </b> the last step, 
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


