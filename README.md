OAA base packages

OkraLinux aarch64 基础软件包的构建源

packages 目录每个 conf 是一个包的配方

scripts/build-package.sh 读配方，下载源码，交叉编译到 aarch64，打包成 oaa

scripts/publish.sh 把配方和产物推到 OkraLinux/oaa-packages

push 到 main 触发 actions 全量构建，也可以手动指定单个包

产物在 okra-packages 仓库的 out 目录

加一个新包，在 packages 里加一个 conf 就行，不用改 workflow

构建机是 ubuntu-24.04-arm，所以产物原生就是 aarch64
