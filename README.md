[![LICENSE](https://img.shields.io/badge/license-Apache--2.0-blue?logo=apache)](https://github.com/IvorySQL/IvorySQL/blob/master/LICENSE)

[![build](https://github.com/IvorySQL/IvorySQL/actions/workflows/build.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/build.yml)
[![Contrib_regression](https://github.com/IvorySQL/IvorySQL/actions/workflows/contrib_regression.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/contrib_regression.yml)
[![meson_build](https://github.com/IvorySQL/IvorySQL/actions/workflows/meson_build.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/meson_build.yml)
[![pg_regression](https://github.com/IvorySQL/IvorySQL/actions/workflows/pg_regression.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/pg_regression.yml)
[![oracle_regression](https://github.com/IvorySQL/IvorySQL/actions/workflows/oracle_regression.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/oracle_regression.yml)
[![oracle_pg_regression](https://github.com/IvorySQL/IvorySQL/actions/workflows/oracle_pg_regression.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/oracle_pg_regression.yml)


![IvorySQL](https://github.com/IvorySQL/Ivory-www/blob/main/static/img/IvorySQL-black.png?raw=true)

IvorySQL is advanced, fully featured, open source Oracle compatible PostgreSQL with a firm commitment to always remain 100% compatible and a Drop-in replacement of the latest PostgreSQL. IvorySQL adds a “compatible_db” toggle switch to switch between Oracle and PostgreSQL compatibility modes.
One of the highlights of IvorySQL is PL/iSQL procedural language that supports oracle’s PL/SQL syntax and Oracle style Packages.

IvorySQL has imported and enhanced the [Orafce](https://github.com/orafce/orafce) extension to add support
for numerous Oracle compatibility features including built-in PACKAGES, data types, and conversion functions

The IvorySQL project is released under the Apache 2 license and encourages all types of contributions. For IvorySQL community no contribution is too small, and we want to thank all our community contributors.

</br>

## We are committed to following the principles of the open source way
We are committed to abiding by the principles of [open-source ways](https://opensource.com/open-source-way) and we strongly believe in building a healthy and inclusive community. We maintain that good ideas can come from anywhere, and the best ideas should win. Only by including diverse perspectives, we can reach the best decision. While the first version of IvorySQL is mainly focused on Oracle Compatibility features, going forward the future road map and feature set will be determined by the community in an open-source way.
</br>

## Compiling from source
IvorySQL can be built on Linux, OSX, Unix and Windows platforms. This section describes the step to compile the source on the Linux based systems.

### Getting the source
Clone the repository with either of the following command:

```bash
git clone https://github.com/IvorySQL/IvorySQL.git
git clone git@github.com:IvorySQL/IvorySQL.git
```


### Requirements

To compile the IvorySQL from the source code, you have to ensure that prerequisite packages are available on the system.

* **Required Packages** The following software packages are required for
  building IvorySQL:

  * **make** - GNU make version 3.80 or newer
  * **gcc** - ISO/ANSI C compiler (at least C99-compliant). Recent versions of
    GCC are recommended.
  * **libreadline** - The GNU Readline library is used by default. 
  * **zlib** - zlib compression library is used by default.
  * **Flex** - (Flex 2.5.31 or later)
  * **Bison** - (Bison 1.875 or later)

* **Optional Packages** The following packages are optional. They are not
  required in the default configuration, but they are needed when certain build
  options are enabled.

  * **libperl** - (Perl 5.8.3 or later) To build the server programming language
    PL/Perl. Perl library installation with the header files. libperl library
    must be a shared library
  * **libpython** - (Python 2.6 or later, Python 3.1 or later) To build the
    PL/Python server programming language. Python installation with the header
    files and the distutils module. libpython library must be a shared library.
  * **Tcl** - (Tcl 8.4 or later) To build the PL/Tcl procedural language.
  * **Gettext API** - (Tcl 8.4 or later) To enable Native Language Support
    (NLS), to display a program's messages in a language other than English.
  * **OpenSSL** - (1.0.1 or later) To support encrypted client connections.
  * **LZ4** - To support compression of data.



### Preparing System
Following are the minimal packages needed to build from source:

```bash
sudo yum install -y bison-devel readline-devel zlib-devel openssl-devel wget
sudo yum groupinstall -y 'Development Tools'
```
### Installation Procedure

* **Configuration** The first step of the installation procedure is to configure
  the source tree for your system and choose the options you would like. This is
  done by running the configure script. For a default installation simply enter:
  ```bash
  ./configure
  ```
  The default configuration will build the server and utilities, as well as all
  client applications and interfaces that require only a C compiler. All files
  will be installed under /usr/local/pgsql by default. You can customize the
  build and installation process by supplying one or more command line options
  to configure see the details
  [here](https://www.postgresql.org/docs/current/install-procedure.html#CONFIGURE-OPTIONS)

* **Build** To start the build, type either of:
  ```
  make
  make all
  ```
* **Regression Tests** To test the newly built server before you install it, you
  can run the regression tests at this point. type either of:
  ```
  make check
  make check-world
  ```
* **Installation** To install, enter:
  ```
  make install
  ```

## Contributing to the IvorySQL
There are plenty of ways to contribute to IvorySQL. You can contribute by providing the documentation updates, by providing the
translations for the documentation. If you have design skills you can contribute to the IvorySQL website project.
Testing the IvorySQL and reporting issues or by issuing pull requests for bug fixes or new features or answering the questions
on mailing lists are some ways to contribute to the IvorySQL project and all types of contributions are welcomed and appreciated
by the IvorySQL community.

* **Join IvorySQL [mailing lists](http://lists.ivorysql.org) to get started**

## Documentation
Please check the [online documentation](https://www.ivorysql.org/docs/next/intro).
