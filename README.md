[![LICENSE](https://img.shields.io/badge/license-Apache--2.0-blue?logo=apache)](https://github.com/IvorySQL/IvorySQL/blob/master/LICENSE)

[![build](https://github.com/IvorySQL/IvorySQL/actions/workflows/build.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/build.yml)
[![Contrib_regression](https://github.com/IvorySQL/IvorySQL/actions/workflows/contrib_regression.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/contrib_regression.yml)
[![meson_build](https://github.com/IvorySQL/IvorySQL/actions/workflows/meson_build.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/meson_build.yml)
[![pg_regression](https://github.com/IvorySQL/IvorySQL/actions/workflows/pg_regression.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/pg_regression.yml)
[![oracle_regression](https://github.com/IvorySQL/IvorySQL/actions/workflows/oracle_regression.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/oracle_regression.yml)

![IvorySQL](https://github.com/IvorySQL/Ivory-www/blob/main/static/img/IvorySQL-black.png?raw=true)

English | [中文](README_CN.md)

IvorySQL is developed based on [PostgreSQL](https://github.com/postgres/postgres). 
IvorySQL is advanced, fully featured, open source Oracle compatible PostgreSQL with a firm commitment to always remain 100% compatible and a Drop-in replacement of the latest PostgreSQL. IvorySQL adds a “compatible_db” toggle switch to switch between Oracle and PostgreSQL compatibility modes.
One of the highlights of IvorySQL is PL/iSQL procedural language that supports oracle’s PL/SQL syntax and Oracle style Packages.

The IvorySQL project is released under the Apache 2 license and encourages all types of contributions. For IvorySQL community no contribution is too small, and we want to thank all our community contributors.

</br>

## We are committed to following the principles of the open source way
We are committed to abiding by the principles of [open-source ways](https://opensource.com/open-source-way) and we strongly believe in building a healthy and inclusive community. We maintain that good ideas can come from anywhere, and the best ideas should win. Only by including diverse perspectives, we can reach the best decision. While the first version of IvorySQL is mainly focused on Oracle Compatibility features, going forward the future road map and feature set will be determined by the community in an open-source way.
</br>

## Installation
We recommend following our [Quick Start](https://docs.ivorysql.org/en/ivorysql-doc/v4.5/v4.5/3#quick-installation) for how to install and running IvorySQL.

Furthermore, for more detailed installation instructions, please refer to the [Installation Docs](https://docs.ivorysql.org/en/ivorysql-doc/v4.5/v4.5/6#introduction). We provide four installation methods for IvorySQL, as outlined below:
- [Yum installation](https://docs.ivorysql.org/en/ivorysql-doc/v4.5/v4.5/6#Yum-installation)
- [Docker installation](https://docs.ivorysql.org/en/ivorysql-doc/v4.5/v4.5/6#Docker-installation)
- [Rpm installation](https://docs.ivorysql.org/en/ivorysql-doc/v4.5/v4.5/6#Rpm-installation)
- [Source code installation](https://docs.ivorysql.org/en/ivorysql-doc/v4.5/v4.5/6#Source-code-installation)

## Developer Formatting hooks and CI:
- A pre-commit formatting hook is provided at `.githooks/pre-commit`. Enable it with `git config core.hooksPath .githooks`, or run `make enable-git-hooks` (equivalently `bash tools/enable-git-hooks.sh`).
- The hook depends only on in-tree tools `src/tools/pgindent` and `src/tools/pg_bsd_indent`. On commit it formats staged C/C++ files with pgindent and re-adds them to the index. 
- A Cirrus workflow `FormatCheck` runs `pgindent --check` on files changed in a PR.

## Contributing to the IvorySQL
There are plenty of ways to contribute to IvorySQL. You can contribute by providing the documentation updates, by providing the
translations for the documentation. If you have design skills you can contribute to the IvorySQL website project.
Testing the IvorySQL and reporting issues or by issuing pull requests for bug fixes or new features or answering the questions
on mailing lists are some ways to contribute to the IvorySQL project and all types of contributions are welcomed and appreciated
by the IvorySQL community.

* **Join IvorySQL [mailing lists](http://lists.ivorysql.org) to get started**

## Documentation
Please check the [online documentation](https://docs.ivorysql.org/).
