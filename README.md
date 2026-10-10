# DeepSeek Harness 本地部署使用说明

本机(Ubuntu 22.04)从源码部署的 DeepSeek Harness —— 你的 fork 仓库,用于后续定制化开发。

本 README 是本地部署说明(原 `usage.md` 的内容,已并入本文件,`usage.md` 不再单独存在);上游原始 README 可通过 `git show HEAD:README.md` 或 [README.zh.md](README.zh.md) 查看。

启停脚本以及运行产物(pid/日志)都在仓库内部。

## 1. 环境概况

| 项目 | 值 |
|---|---|
| 仓库路径 | `/home/liurenyu/src/lry-deepseek-harness` |
| 远端 | `origin` = `https://github.com/liu-ry/lry-deepseek-harness.git`(你的 fork) |
| 分支 | `master`,浅克隆(`--depth 1`, `.git` 约 39 MB) |
| Node.js | 通过 nvm 使用 **v24.18.0**(仓库要求 `^22.19 || >=24`;系统默认的 `/usr/bin/node` 是 v20,不满足) |
| 包管理器 | pnpm `11.28.5`,由 corepack 按 `package.json` 的 `packageManager` 自动选用 |
| 依赖 / 构建 | 已执行 `pnpm install` + `pnpm run build`(约 2.5 GB,含 `node_modules`) |
| 启停脚本 | 仓库根目录 `./dsh.sh` |
| 本文档 | 仓库根目录 `./README.md` |
| 日志 / PID | 仓库内 `./.dsh-run/dsh-web.log`、`./.dsh-run/dsh-web.pid` |

`.dsh-run/` 是运行产物目录,已写入 `.git/info/exclude`(仅本地忽略,不改动仓库的 `.gitignore`),因此 `git status` 不会被它弄脏。

## 2. 用脚本启停(推荐)

```sh
cd /home/liurenyu/src/lry-deepseek-harness
./dsh.sh start      # 后台启动,打印带 token 的访问地址
./dsh.sh status     # 查看状态
./dsh.sh stop       # 停止
./dsh.sh restart    # 重启
./dsh.sh url        # 只打印当前访问地址
./dsh.sh logs       # 实时跟踪日志(Ctrl-C 退出)
./dsh.sh build      # 装依赖 + 重新构建(改代码后用)
```

可覆盖的默认值(用环境变量):

```sh
DSH_PORT=8080 ./dsh.sh start
DSH_REPO=/别的/路径 ./dsh.sh start
DSH_RUN_DIR=/tmp/dsh-run ./dsh.sh start   # 把 pid/日志挪出仓库
```

## 3. 手动启停(不使用脚本)

每次新开终端都要先切到 Node 24:

```sh
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm use 24
cd /home/liurenyu/src/lry-deepseek-harness
corepack pnpm dsh web --no-open          # 前台启动,Ctrl-C 停止
```

后台运行并抓取访问地址:

```sh
cd /home/liurenyu/src/lry-deepseek-harness
setsid nohup corepack pnpm dsh web --no-open > ~/dsh-web.log 2>&1 < /dev/null &
cat ~/dsh-web.log                        # 里面那行 "dsh web: http://..." 就是地址
```

停止:

```sh
pkill -f "apps/cli/src/bin[.]ts"
```

> 注意 `pkill -f` 的模式要写成 `bin[.]ts` 这种带字符类的形式。直接写 `bin.ts`,模式字符串会匹配到执行它的那条 shell 命令行本身,把自己一起杀掉(表现为命令无输出、退出码 143)。

## 4. 访问与首次配置

启动后会打印:

```
dsh web: http://127.0.0.1:3080/?token=<TOKEN>
```

**必须带 token 访问**,不带 token 会返回 401。token 每次重启都会变,以最新日志/脚本输出为准;浏览器首次带 token 打开后会种下 cookie,之后可直接访问 `http://127.0.0.1:3080/`。

进来后还需要两步才能真正跑 agent:

1. **配置模型**:打开 *设置 → 模型*,填入 [DeepSeek API key](https://platform.deepseek.com/)。生效即时,无需重启。
2. **选择工作区**:点 *选择工作区*,加入你想让 agent 操作的目录;选中之后会话输入框才可用。

也可以用 `.env` 提供凭证(仓库根目录的 `.env` 已被 gitignore):

```sh
cd /home/liurenyu/src/lry-deepseek-harness
echo 'DEEPSEEK_API_KEY=sk-...' >> .env
# 可选: echo 'DEEPSEEK_BASE_URL=https://...' >> .env
```

## 5. 改代码后怎么生效

`pnpm dsh web` 直接使用已构建产物,**不会自动重建**:

```sh
./dsh.sh build && ./dsh.sh restart      # 改完源码:重建 + 重启
```

开发时更省事的做法(一条命令里构建、启动、监听 client 改动自动重建):

```sh
cd /home/liurenyu/src/lry-deepseek-harness
corepack pnpm run dev:web
```

只跑类型检查 / 测试 / 代码规范:

```sh
corepack pnpm run typecheck
corepack pnpm run test
corepack pnpm run lint
```

## 6. 从别的机器访问

服务默认只监听 `127.0.0.1`,只能本机访问。两种方式:

**SSH 隧道**(最简单):在你自己的电脑上执行

```sh
ssh -L 3080:127.0.0.1:3080 <用户名>@<这台机器的地址>
```

然后本地浏览器打开 `http://127.0.0.1:3080/?token=<TOKEN>`。

**反向代理**:参考仓库里的 `docs/user/guide/public-deployments.zh.md`,配合 `--public-url` 和 `--trusted-host` 参数使用。注意 `--host` 只接受具体网卡的 IP 字面量,不接受 `0.0.0.0`。

## 7. 常见问题

**`pnpm: command not found` / 版本不对**
先 `corepack enable`,再在仓库目录里用 `corepack pnpm ...`。仓库固定 `pnpm@11.28.5`,corepack 会自动匹配。

**构建报 Node 版本或 TypeScript 加载错误**
确认 `node -v` 是 v22.19+ 或 v24+。默认 shell 里的 `node` 是 v20,必须先 `nvm use 24`。

**访问端口返回 502**
本机设了 `http_proxy/all_proxy`(如 `127.0.0.1:7890`),curl 请求被代理拦截了。测试时加 `--noproxy '*'`:

```sh
curl --noproxy '*' -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3080/
```

**启动日志里警告 `all_proxy names a SOCKS proxy`**
无害。是环境变量 `all_proxy=socks://...` 导致的,不影响运行。

**端口被占用**
`ss -ltnp | grep 3080` 查占用者,或 `DSH_PORT=8080 ./dsh.sh start` 换端口。

**需要完整 git 历史 / 想同步上游**
当前是浅克隆。补全历史:`git fetch --unshallow`。加官方上游:

```sh
git remote add upstream https://github.com/deepseek-ai/deepseek-harness.git
git fetch upstream
```

**harness 自身状态目录**
`~/.dsh` 存放运行状态(会话、身份等),删掉会丢失历史会话记录。
