[![LICENSE](https://img.shields.io/badge/license-Apache--2.0-blue?logo=apache)](https://github.com/IvorySQL/IvorySQL/blob/master/LICENSE)

[![build](https://github.com/IvorySQL/IvorySQL/actions/workflows/build.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/build.yml)
[![Contrib_regression](https://github.com/IvorySQL/IvorySQL/actions/workflows/contrib_regression.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/contrib_regression.yml)
[![meson_build](https://github.com/IvorySQL/IvorySQL/actions/workflows/meson_build.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/meson_build.yml)
[![pg_regression](https://github.com/IvorySQL/IvorySQL/actions/workflows/pg_regression.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/pg_regression.yml)
[![oracle_regression](https://github.com/IvorySQL/IvorySQL/actions/workflows/oracle_regression.yml/badge.svg?branch=master&event=push)](https://github.com/IvorySQL/IvorySQL/actions/workflows/oracle_regression.yml)

![IvorySQL](https://github.com/IvorySQL/Ivory-www/blob/main/static/img/IvorySQL-black.png?raw=true)

[English](README.md) | 中文

IvorySQL 基于开源[PostgreSQL](https://github.com/postgres/postgres)数据库。是一款先进、功能全面的开源 Oracle 兼容 PostgreSQL，始终承诺100% 兼容最新版本的 PostgreSQL，并可作为其无缝替代方案。IvorySQL 增加了一个 “compatible_db” 开关，支持在 Oracle 和 PostgreSQL 兼容模式之间自由切换。IvorySQL 的一大亮点是 PL/iSQL 过程式语言，它兼容 Oracle 的 PL/SQL 语法并支持 Oracle 风格的 Package。

IvorySQL 项目采用 Apache 2.0 许可协议发布，并鼓励各种形式的社区贡献。在 IvorySQL 社区中，每一份贡献都至关重要，我们由衷感谢所有社区贡献者的支持！

</br>

## 开发者代码格式化
- 提交前自动格式化（推荐）：
  - 已克隆仓库：在仓库根目录执行 `make enable-git-hooks`（或 `bash tools/enable-git-hooks.sh`）
- 提交时行为：Git 钩子会自动用 `pgindent` 格式化已暂存的 C/C++ 文件并回加到暂存区，未通过二次校验会阻止提交。
- PR 阶段：Cirrus 将运行 `FormatCheck`（pgindent --check）对差异文件做只读校验。

## 我们致力于遵循开源理念的原则
我们致力于遵循[开源之道](https://opensource.com/open-source-way)的原则，并坚定地相信构建一个健康且包容的社区至关重要。我们始终坚信，优秀的想法可以来源于任何地方，而最优的想法应当脱颖而出。只有在多元观点的碰撞下，才能做出最明智的决策。尽管 IvorySQL 的首个版本主要聚焦于 Oracle 兼容性功能，但未来的路线图和功能集将由社区以开源的方式共同决定。
</br>

## 安装
建议参考[快速入门](https://docs.ivorysql.org/cn/ivorysql-doc/v4.5/v4.5/3#quick-installation)了解如何安装和运行IvorySQL。

此外，关于更详细的安装说明，请参阅[安装文档](https://docs.ivorysql.org/cn/ivorysql-doc/v4.5/v4.5/6#introduction)。我们提供以下四种 IvorySQL 的安装方法：
- [Yum 安装](https://docs.ivorysql.org/cn/ivorysql-doc/v4.5/v4.5/6#yum源安装)
- [Docker 安装](https://docs.ivorysql.org/cn/ivorysql-doc/v4.5/v4.5/6#docker安装)
- [RPM 安装](https://docs.ivorysql.org/cn/ivorysql-doc/v4.5/v4.5/6#rpm安装)
- [源代码安装](https://docs.ivorysql.org/cn/ivorysql-doc/v4.5/v4.5/6#源码安装)



## 为IvorySQL做贡献
有许多方式可以为 IvorySQL 做出贡献。您可以通过更新文档或提供文档翻译来贡献。如果您具备设计技能，还可以参与 IvorySQL 官网项目的建设。

测试 IvorySQL 并报告问题、提交错误修复或新功能的 Pull Request，或者在邮件列表中回答问题，都是为 IvorySQL 贡献的方式。IvorySQL 社区欢迎并感谢所有类型的贡献。

* **加入IvorySQL [邮件列表](http://lists.ivorysql.org) 即刻开始！**

## 文档
请查看[在线文档](https://docs.ivorysql.org/)。
