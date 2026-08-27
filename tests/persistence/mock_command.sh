#!/bin/sh
# tests/persistence/mock_command.sh
#
# サンドボックス化されたコピー (instrument_gui.sh / instrument_helper.sh の
# 出力) が実行時に呼び出す全コマンドを $SANDBOX/bin へ書き出す。
#
# 3分類:
#   1) 読み取り専用パススルー: 実バイナリを無条件でexecする。
#      awk grep sed cut tail sleep
#   2) sandbox制限ラッパー: 対象パスがsandbox配下であることを確認した
#      うえで実バイナリへ委譲する。sandbox外を指す場合は exit 99。
#      mkdir rmdir rm cat mktemp ls
#   3) 完全モック: 実バイナリを一切execしない。
#      lsblk findmnt id stat parted mkfs.ext4 mount umount partprobe
#      udevadm wipefs sudo yad sync
#
# ls は本来ただの読み取り専用パススルーだが、失敗マトリクス
# (test_helper_failure_matrix.sh) がcheck_holders_emptyの
# `ls -A .../holders` 失敗経路 (終了コード14) を、実UID・パーミッションに
# 依存せず決定論的に再現できるよう、既定値0のopt-in環境変数
# (MOCK_FAIL_LS_HOLDERS) による失敗注入だけを追加した2分類側のラッパーと
# する (chmod 000等のパーミッション操作はharnessがroot実行された場合に
# 無力化されるため使わない)。
#
# 初回PRでは kill を意図的に配置しない (GUI本体のkill呼び出しは
# "2>/dev/null || :" で保護されており、コマンド不在 [exit 127] も
# 許容される設計であることを production ソースで確認済み)。
#
# 呼び出し側 (test_gui.sh / test_helper.sh) は、write_mocks を呼ぶ前に
# create_sandbox 済みであること。生成される各モックは、実行時に自分
# 自身の環境変数 (SANDBOX、MOCK_*) を読んで応答を決める。
set -eu

# passthrough_allowlist: このリストに無いコマンド名は write_mocks が
# 自動でpassthrough化しない (項目9)。
PASSTHROUGH_ALLOWLIST='awk grep sed cut tail sleep'

write_mocks() {
    # write_mocks SANDBOX
    sandbox="$1"
    bin="$sandbox/bin"

    # ---- 分類1: 読み取り専用パススルー -----------------------------------
    for cmd in $PASSTHROUGH_ALLOWLIST; do
        real="/usr/bin/$cmd"
        [ -x "$real" ] || real="/bin/$cmd"
        cat > "$bin/$cmd" <<EOF
#!/bin/sh
exec $real "\$@"
EOF
        chmod +x "$bin/$cmd"
    done

    # ---- 分類2: sandbox制限ラッパー ---------------------------------------
    cat > "$bin/mkdir" <<EOF
#!/bin/sh
SANDBOX='$sandbox'
past_dd=0
for a in "\$@"; do
    if [ "\$past_dd" -eq 1 ]; then
        case "\$a" in
            "\$SANDBOX"/*) ;;
            *) echo "mock mkdir: REFUSING path outside sandbox: \$a" >&2; exit 99 ;;
        esac
    fi
    case "\$a" in
        --) past_dd=1 ;;
        --*) ;;
        -*) ;;
        *)
            case "\$a" in
                "\$SANDBOX"/*) ;;
                *) echo "mock mkdir: REFUSING path outside sandbox: \$a" >&2; exit 99 ;;
            esac
            ;;
    esac
done
exec /usr/bin/mkdir "\$@"
EOF
    chmod +x "$bin/mkdir"

    for cmd in rm; do
        cat > "$bin/$cmd" <<EOF
#!/bin/sh
SANDBOX='$sandbox'
past_dd=0
for a in "\$@"; do
    if [ "\$past_dd" -eq 1 ]; then
        case "\$a" in
            "\$SANDBOX"/*) ;;
            *) echo "mock $cmd: REFUSING path outside sandbox: \$a" >&2; exit 99 ;;
        esac
    fi
    case "\$a" in
        --) past_dd=1 ;;
        --*) ;;
        -*) ;;
        *)
            case "\$a" in
                "\$SANDBOX"/*) ;;
                *) echo "mock $cmd: REFUSING path outside sandbox: \$a" >&2; exit 99 ;;
            esac
            ;;
    esac
done
exec /usr/bin/$cmd "\$@"
EOF
        chmod +x "$bin/$cmd"
    done

    # rmdirは、失敗マトリクス (後始末失敗の再現) 用に、自身のロック
    # ディレクトリ・一時マウントディレクトリのそれぞれに対してだけ、
    # 明示的なopt-in環境変数 (MOCK_FAIL_RMDIR_LOCK/MOCK_FAIL_RMDIR_MNT、
    # いずれも既定値0) が'1'の場合にのみ失敗を注入する。両方とも未設定
    # (既定) の場合の挙動は、rm/mkdir等と同じsandbox制限ラッパー
    # (実rmdirへ委譲) のままであり、既存シナリオへの影響はない。
    cat > "$bin/rmdir" <<EOF
#!/bin/sh
SANDBOX='$sandbox'
past_dd=0
for a in "\$@"; do
    if [ "\$past_dd" -eq 1 ]; then
        case "\$a" in
            "\$SANDBOX"/*) ;;
            *) echo "mock rmdir: REFUSING path outside sandbox: \$a" >&2; exit 99 ;;
        esac
        case "\$a" in
            */mypocketos-persistence-setup-helper.lock)
                if [ "\${MOCK_FAIL_RMDIR_LOCK:-0}" = '1' ]; then
                    echo "mock rmdir: injected failure (lock dir): \$a" >&2
                    exit 1
                fi
                ;;
            */mypocketos-persistence-setup-helper.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9])
                if [ "\${MOCK_FAIL_RMDIR_MNT:-0}" = '1' ]; then
                    echo "mock rmdir: injected failure (mnt dir): \$a" >&2
                    exit 1
                fi
                ;;
        esac
    fi
    case "\$a" in
        --) past_dd=1 ;;
        --*) ;;
        -*) ;;
        *)
            case "\$a" in
                "\$SANDBOX"/*) ;;
                *) echo "mock rmdir: REFUSING path outside sandbox: \$a" >&2; exit 99 ;;
            esac
            ;;
    esac
done
exec /usr/bin/rmdir "\$@"
EOF
    chmod +x "$bin/rmdir"

    # /proc/cmdline・/proc/swapsへの特殊応答は、ファイル引数が正確に1件
    # (他の引数・オプションを伴わない) の場合だけ許可する。余分な引数・
    # 未知のオプションが混ざる場合や、対象がその2ファイルでない場合は、
    # 通常のsandbox制限ラッパー (実catへ委譲、対象パスがsandbox配下で
    # あることを確認) にfall throughする。
    cat > "$bin/cat" <<EOF
#!/bin/sh
SANDBOX='$sandbox'
if [ "\$#" -eq 0 ]; then
    exec /usr/bin/cat
fi
if [ "\$#" -eq 1 ]; then
    case "\$1" in
        "\$SANDBOX/proc/cmdline")
            if [ "\${MOCK_FAIL_CMDLINE:-0}" = '1' ]; then
                exit 1
            fi
            printf '%s' "\${MOCK_CMDLINE:-BOOT_IMAGE=/live/vmlinuz boot=live nopersistence quiet}"
            exit 0
            ;;
        "\$SANDBOX/proc/swaps")
            if [ "\${MOCK_FAIL_SWAPS_READ:-0}" = '1' ]; then
                exit 1
            fi
            if [ "\${MOCK_EMPTY_SWAPS_FILE:-0}" = '1' ]; then
                exit 0
            fi
            printf '%s\n' 'Filename                                Type            Size            Used            Priority'
            if [ -n "\${MOCK_SWAP_LINE:-}" ]; then
                printf '%s\n' "\$MOCK_SWAP_LINE"
            fi
            exit 0
            ;;
    esac
fi
if [ "\$#" -eq 2 ] && [ "\$1" = '--' ]; then
    case "\$2" in
        */persistence.conf)
            if [ -n "\${MOCK_FAKE_CONF_CONTENT:-}" ]; then
                case "\$2" in
                    "\$SANDBOX"/*) ;;
                    *) echo "mock cat: REFUSING path outside sandbox: \$2" >&2; exit 99 ;;
                esac
                printf '%s' "\$MOCK_FAKE_CONF_CONTENT"
                exit 0
            fi
            ;;
    esac
fi
for a in "\$@"; do
    case "\$a" in
        --) continue ;;
        "\$SANDBOX"/*) ;;
        *)
            echo "mock cat: REFUSING path outside sandbox: \$a" >&2
            exit 99
            ;;
    esac
done
exec /usr/bin/cat "\$@"
EOF
    chmod +x "$bin/cat"

    cat > "$bin/mktemp" <<EOF
#!/bin/sh
SANDBOX='$sandbox'
mode=''
template=''
for a in "\$@"; do
    case "\$a" in
        -d) mode='d' ;;
        -*) ;;
        *) template="\$a" ;;
    esac
done
if [ "\$mode" != 'd' ] || [ -z "\$template" ]; then
    echo "mock mktemp: REFUSING unsupported invocation: \$*" >&2
    exit 98
fi
case "\$template" in
    "\$SANDBOX"/*) ;;
    *)
        echo "mock mktemp: REFUSING template outside sandbox: \$template" >&2
        exit 99
        ;;
esac
if [ "\${MOCK_FAIL_MKTEMP:-0}" = '1' ]; then
    exit 1
fi
result="\$(/usr/bin/mktemp -d -- "\$template")"
case "\$result" in
    "\$SANDBOX"/*) ;;
    *)
        echo "mock mktemp: real mktemp returned a path outside sandbox: \$result" >&2
        exit 99
        ;;
esac
printf '%s\n' "\$result"
EOF
    chmod +x "$bin/mktemp"

    # lsは通常はsandbox制限ラッパー (実lsへ委譲) だが、対象が".../holders"
    # で終わり、かつ既定値0のopt-in環境変数 MOCK_FAIL_LS_HOLDERS が'1'の
    # 場合だけ、実lsを一切呼ばずに失敗を注入する (実UID root下でも
    # パーミッションに依存せず決定論的に失敗させるため)。
    cat > "$bin/ls" <<EOF
#!/bin/sh
SANDBOX='$sandbox'
past_dd=0
target=''
for a in "\$@"; do
    if [ "\$past_dd" -eq 1 ]; then
        case "\$a" in
            "\$SANDBOX"/*) ;;
            *) echo "mock ls: REFUSING path outside sandbox: \$a" >&2; exit 99 ;;
        esac
        target="\$a"
    fi
    case "\$a" in
        --) past_dd=1 ;;
        --*) ;;
        -*) ;;
        *)
            case "\$a" in
                "\$SANDBOX"/*) ;;
                *) echo "mock ls: REFUSING path outside sandbox: \$a" >&2; exit 99 ;;
            esac
            target="\$a"
            ;;
    esac
done
case "\$target" in
    */holders)
        if [ "\${MOCK_FAIL_LS_HOLDERS:-0}" = '1' ]; then
            echo "mock ls: injected failure (holders): \$target" >&2
            exit 1
        fi
        ;;
esac
exec /usr/bin/ls "\$@"
EOF
    chmod +x "$bin/ls"

    # mock-kill: 完全モック。実killは一切実行せず、実プロセスへシグナルを
    # 送らない。instrument_gui.sh が production の kill 呼び出しを、この
    # スクリプトへの絶対パス呼び出しへ書き換える (dash組み込みのkillは
    # 絶対パスでは使われず、必ず外部コマンドとしてexecされるため)。
    cat > "$bin/mock-kill" <<EOF
#!/bin/sh
SANDBOX='$sandbox'
if [ "\$#" -eq 2 ] && [ "\$1" = '-0' ]; then
    printf '%s %s\n' "\$1" "\$2" >> "\$SANDBOX/work/mock-kill-invocations"
    exit "\${MOCK_KILL_0_RC:-1}"
fi
if [ "\$#" -eq 1 ]; then
    printf '%s\n' "\$1" >> "\$SANDBOX/work/mock-kill-invocations"
    exit 0
fi
echo "mock-kill: unknown argument form: \$*" >&2
exit 98
EOF
    chmod +x "$bin/mock-kill"

    # ---- 分類3: 完全モック (実バイナリを一切execしない) -------------------

    cat > "$bin/id" <<'EOF'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = '-u' ]; then
    printf '%s\n' "${MOCK_UID:-0}"
    exit 0
fi
echo "mock id: unknown argument form: $*" >&2
exit 98
EOF
    chmod +x "$bin/id"

    # 許可する形式は次の2つに厳密に限定する (production の実呼び出しの
    # みに一致させる)。書式指定子を引数の個数から独立に判定せず、
    # 「3引数なら%uのみ」「4引数 (--付き) なら%sのみ」というproductionの
    # 実際の呼び出し形に1対1で固定する。
    #   3引数: stat -c %u SANDBOX配下のパス           (GUI)
    #   4引数: stat -c %s -- SANDBOX配下のパス        (helper)
    # それ以外の引数構成・書式指定子は未知の形式としてexit 98、対象パスが
    # sandbox外の場合はexit 99とし、実statは一切呼び出さない。
    cat > "$bin/stat" <<EOF
#!/bin/sh
SANDBOX='$sandbox'
if [ "\$#" -eq 3 ] && [ "\$1" = '-c' ] && [ "\$2" = '%u' ]; then
    fmt='%u'; path="\$3"
elif [ "\$#" -eq 4 ] && [ "\$1" = '-c' ] && [ "\$2" = '%s' ] && [ "\$3" = '--' ]; then
    fmt='%s'; path="\$4"
else
    echo "mock stat: unknown argument form: \$*" >&2
    exit 98
fi
case "\$path" in
    "\$SANDBOX"/*) ;;
    *)
        echo "mock stat: REFUSING path outside sandbox: \$path" >&2
        exit 99
        ;;
esac
case "\$fmt" in
    '%u')
        printf '%s' "\${MOCK_STAT_UID:-0}"
        exit 0
        ;;
    '%s')
        printf '%s' "\${MOCK_CONF_SIZE:-6}"
        exit 0
        ;;
    *)
        echo "mock stat: unknown format: \$fmt" >&2
        exit 98
        ;;
esac
EOF
    chmod +x "$bin/stat"

    cat > "$bin/findmnt" <<EOF
#!/bin/sh
SANDBOX='$sandbox'
has_raw=0; has_pairs=0; has_mp=0; has_tgt=0
colspec=''; target=''; prev=''
for a in "\$@"; do
    case "\$a" in
        -r|--raw) has_raw=1 ;;
        -P|--pairs) has_pairs=1 ;;
        --mountpoint) has_mp=1 ;;
        --target) has_tgt=1 ;;
    esac
    case "\$a" in
        -*r*) case "\$a" in --*) ;; *) has_raw=1 ;; esac ;;
    esac
    if [ "\$prev" = '-o' ]; then colspec="\$a"; fi
    if [ "\$prev" = '--mountpoint' ] || [ "\$prev" = '--target' ]; then target="\$a"; fi
    prev="\$a"
done

if [ "\$has_raw" -eq 1 ] && [ "\$has_pairs" -eq 1 ]; then
    echo "mock findmnt: -r/-P cannot be combined (matches real findmnt behavior)" >&2
    exit 1
fi

if [ "\$has_mp" -eq 1 ]; then
    case "\$target" in
        */live/medium)
            exit "\${MOCK_LIVE_MEDIUM_MOUNTED:-0}"
            ;;
        *)
            state="\$(cat "\$SANDBOX/work/mount-state" 2>/dev/null)" || state=''
            [ "\$state" = "\$target" ]
            exit \$?
            ;;
    esac
fi

if [ "\$has_tgt" -eq 1 ]; then
    case "\$colspec" in
        SOURCE)
            [ "\${MOCK_FAIL_LIVE_SOURCE:-0}" = '1' ] && exit 1
            printf '%s\n' "\${MOCK_LIVE_SOURCE:-\$SANDBOX/dev/fakedisk}"
            exit 0
            ;;
        SOURCE,FSTYPE)
            [ "\${MOCK_FAIL_HOME_SOURCE:-0}" = '1' ] && exit 1
            printf 'SOURCE="%s" FSTYPE="%s"\n' "\${MOCK_HOME_SOURCE:-overlay}" "\${MOCK_HOME_FSTYPE:-overlay}"
            exit 0
            ;;
    esac
fi

echo "mock findmnt: unrecognized invocation: \$*" >&2
exit 1
EOF
    chmod +x "$bin/findmnt"

    cat > "$bin/lsblk" <<EOF
#!/bin/sh
inverse=0; raw=0
colspec=''; dev=''; past_dd=0; prev=''
for a in "\$@"; do
    if [ "\$past_dd" -eq 1 ] && [ -z "\$dev" ]; then
        dev="\$a"
    fi
    case "\$a" in
        --) past_dd=1 ;;
        -s) inverse=1 ;;
        --*) ;;
        -*) case "\$a" in *r*) raw=1 ;; esac ;;
    esac
    if [ "\$prev" = '-o' ]; then colspec="\$a"; fi
    prev="\$a"
done

if [ "\$inverse" -eq 1 ] && [ "\$colspec" = 'KNAME' ]; then
    if [ "\${MOCK_FAIL_ANCESTOR_CHAIN:-0}" = '1' ]; then
        exit 1
    fi
    if [ -n "\${MOCK_ANCESTOR_CHAIN:-}" ]; then
        printf '%s\n' "\$MOCK_ANCESTOR_CHAIN" | while IFS= read -r k; do
            [ -n "\$k" ] && printf 'KNAME="%s"\n' "\$k"
        done
        exit 0
    fi
    printf 'KNAME="%s"\n' "\${MOCK_ANCESTOR_KNAME:-unrelated-disk}"
    exit 0
fi

case "\$colspec" in
    'NAME,KNAME,PATH,MAJ:MIN,TYPE,SIZE,RO,RM,HOTPLUG,MOUNTPOINTS,FSTYPE,PTTYPE,LABEL,PARTLABEL,PKNAME,MODEL,SERIAL,TRAN')
        cat "\${MOCK_ALL_ROWS_FILE:?MOCK_ALL_ROWS_FILE not set}"
        exit 0
        ;;
    'NAME,TYPE,MOUNTPOINTS')
        cat "\${MOCK_DISK_ROWS_FILE:?MOCK_DISK_ROWS_FILE not set}"
        exit 0
        ;;
    'NAME,PATH,TYPE,PKNAME,MAJ:MIN')
        cat "\${MOCK_PART_ROWS_FILE:?MOCK_PART_ROWS_FILE not set}"
        exit 0
        ;;
    LABEL)
        printf '%s\n' "\${MOCK_LABEL_ROWS:-LABEL=\"\"}"
        exit 0
        ;;
    PARTLABEL)
        printf '%s\n' "\${MOCK_PARTLABEL_ROWS:-PARTLABEL=\"\"}"
        exit 0
        ;;
    PATH)
        if [ "\$dev" = "\${FAKE_DEVICE:-}" ]; then
            printf '%s\n' "\${MOCK_LSBLK_PATH:-\$dev}"
        else
            printf '%s\n' "\${MOCK_PART_PATH_FIELD:-\$dev}"
        fi
        exit 0
        ;;
    KNAME)
        if [ "\$dev" = "\${FAKE_DEVICE:-}" ]; then
            printf '%s\n' "\${MOCK_LSBLK_KNAME:-fakedisk}"
        else
            printf '%s\n' "\${MOCK_SWAP_KNAME:-unrelated-kname}"
        fi
        exit 0
        ;;
    TYPE)
        if [ "\$dev" = "\${FAKE_DEVICE:-}" ]; then
            printf '%s\n' "\${MOCK_LSBLK_TYPE:-disk}"
        else
            printf '%s\n' "\${MOCK_PART_TYPE:-part}"
        fi
        exit 0
        ;;
    RO)
        if [ "\$dev" = "\${FAKE_DEVICE:-}" ]; then
            printf '%s\n' "\${MOCK_LSBLK_RO:-0}"
        else
            printf '%s\n' "\${MOCK_PART_RO:-0}"
        fi
        exit 0
        ;;
    'MAJ:MIN')
        if [ "\$dev" = "\${FAKE_DEVICE:-}" ]; then
            val="\${MOCK_LSBLK_MAJMIN:-254:0}"
        else
            val="\${MOCK_PART_MAJMIN:-254:1}"
        fi
        if [ "\$raw" -eq 1 ]; then
            printf '%s' "\$val"
        else
            printf '%s' "\$val  "
        fi
        exit 0
        ;;
    PTTYPE)
        printf '%s\n' "\${MOCK_LSBLK_PTTYPE:-}"
        exit 0
        ;;
    PKNAME)
        printf '%s\n' "\${MOCK_LSBLK_PKNAME:-fakedisk}"
        exit 0
        ;;
esac

echo "mock lsblk: unrecognized invocation: \$*" >&2
exit 1
EOF
    chmod +x "$bin/lsblk"

    cat > "$bin/parted" <<EOF
#!/bin/sh
: > "$sandbox/work/parted-called"
printf '%s\n' "\$*" >> "$sandbox/work/parted-invocations"
case "\$*" in
    *mklabel\\ gpt*) [ "\${MOCK_FAIL_GPT:-0}" = '1' ] && exit 1; exit 0 ;;
    *mkpart*) [ "\${MOCK_FAIL_MKPART:-0}" = '1' ] && exit 1; exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$bin/parted"

    cat > "$bin/mkfs.ext4" <<EOF
#!/bin/sh
: > "$sandbox/work/mkfs-called"
[ "\${MOCK_FAIL_MKFS:-0}" = '1' ] && exit 1
exit 0
EOF
    chmod +x "$bin/mkfs.ext4"

    cat > "$bin/partprobe" <<EOF
#!/bin/sh
: > "$sandbox/work/partprobe-called"
[ "\${MOCK_FAIL_PARTPROBE:-0}" = '1' ] && exit 1
exit 0
EOF
    chmod +x "$bin/partprobe"

    cat > "$bin/udevadm" <<EOF
#!/bin/sh
: > "$sandbox/work/udevadm-called"
[ "\${MOCK_FAIL_UDEVADM:-0}" = '1' ] && exit 1
exit 0
EOF
    chmod +x "$bin/udevadm"

    cat > "$bin/wipefs" <<'EOF'
#!/bin/sh
tgt="${*##* }"
if [ "$tgt" = "${FAKE_DEVICE:-}" ]; then
    [ "${MOCK_FAIL_WIPEFS_DEVICE:-0}" = '1' ] && exit 1
    printf '%s' "${MOCK_WIPEFS_SIG:-}"
else
    [ "${MOCK_FAIL_WIPEFS_PART:-0}" = '1' ] && exit 1
    printf '%s' "${MOCK_PART_WIPEFS_SIG:-}"
fi
exit 0
EOF
    chmod +x "$bin/wipefs"

    # MOCK_CONF_PATH_IS_DIR: persistence.confの書き込み失敗
    # (helper側の終了コード24) を決定論的に再現するためのフック。
    # パーミッション (chmod) による再現は、harnessが実UIDrootで動く場合に
    # 書き込みが成功してしまい非決定的になるため使わない。代わりに、
    # helper本体が持つ変数が指す予定の位置 (マウント先ディレクトリ直下の
    # persistence.conf) へ、helper本体が書き込む前に空ディレクトリを
    # 作っておく。そこへのファイル書き込み (printfによるリダイレクト) は
    # EISDIR (書き込み先がディレクトリ) で失敗し、これはUID・パーミッ
    # ションに関係なくカーネルが返すエラーであるため、root実行下でも
    # 確実に失敗する。
    #
    # 注意 (このブロック配下のheredocは全て非quoted <<EOF であり、
    # コメント行であっても書いたドル記号付きの変数参照はモック本体では
    # なくwrite_mocks自身のこのシェルで展開される): heredocの本文中に
    # このスクリプト (write_mocks) が知らない変数名をドル記号付きで
    # 書かないこと。書くと、その変数が未定義である限りwrite_mocks自体が
    # "parameter not set" エラーを出す (dashでは即座の異常終了とは
    # 限らないため、この種の書き間違いはPASS表示に紛れて見逃されやすい)。
    cat > "$bin/mount" <<EOF
#!/bin/sh
: > "$sandbox/work/mount-called"
[ "\${MOCK_FAIL_MOUNT:-0}" = '1' ] && exit 1
shift
shift
dst="\$1"
printf '%s' "\$dst" > "$sandbox/work/mount-state"
if [ "\${MOCK_CONF_PATH_IS_DIR:-0}" = '1' ]; then
    mkdir -- "\$dst/persistence.conf" 2>/dev/null || :
fi
exit 0
EOF
    chmod +x "$bin/mount"

    cat > "$bin/umount" <<EOF
#!/bin/sh
: > "$sandbox/work/umount-called"
[ "\${MOCK_FAIL_UMOUNT:-0}" = '1' ] && exit 1
shift
target="\$1"
state="\$(cat "$sandbox/work/mount-state" 2>/dev/null)" || state=''
if [ "\$state" = "\$target" ]; then
    if [ -d "\$target/persistence.conf" ] && [ ! -L "\$target/persistence.conf" ]; then
        # MOCK_CONF_PATH_IS_DIRが作った注入用の空ディレクトリを取り除く
        # (中身は作っていないため常に空のはず、rmdirで十分)。
        rmdir -- "\$target/persistence.conf" 2>/dev/null || :
    elif [ -e "\$target/persistence.conf" ]; then
        # umount (アンマウント) によって内容が失われる前に、検証用の退避
        # コピーをsandbox/workへ保存しておく。cp はこのモックのPATH
        # (sandbox binのみ) に存在しないため、sandbox化済みの cat モック +
        # シェルのリダイレクト (外部コマンドを要しない) で退避する。
        cat -- "\$target/persistence.conf" > "$sandbox/work/persistence.conf.snapshot" 2>/dev/null || :
        rm -f "\$target/persistence.conf" 2>/dev/null || :
    fi
    : > "$sandbox/work/mount-state"
fi
exit 0
EOF
    chmod +x "$bin/umount"

    cat > "$bin/sync" <<EOF
#!/bin/sh
: > "$sandbox/work/sync-called"
[ "\${MOCK_FAIL_SYNC:-0}" = '1' ] && exit 1
exit 0
EOF
    chmod +x "$bin/sync"

    cat > "$bin/sudo" <<EOF
#!/bin/sh
: > "$sandbox/work/sudo-called"
printf 'x\n' >> "$sandbox/work/sudo-invocations"
if [ "\${MOCK_SUDO_FAIL:-0}" = '1' ]; then
    printf 'sudo: a password is required\n' >&2
    exit 1
fi
if [ -n "\${MOCK_HELPER_STDOUT:-}" ]; then
    printf '%s\n' "\$MOCK_HELPER_STDOUT"
fi
if [ -n "\${MOCK_HELPER_STDERR:-}" ]; then
    printf '%s\n' "\$MOCK_HELPER_STDERR" >&2
fi
exit "\${MOCK_HELPER_RC:-0}"
EOF
    chmod +x "$bin/sudo"

    cat > "$bin/yad" <<EOF
#!/bin/sh
case "\$*" in
    *--list*)
        # GUIが渡す候補データ (パス・サイズ・モデル・シリアル番号・接続
        # 方式を1行ずつ) をそのまま検証用に保存する。stdinを読み切って
        # おくことで、pipeの向こう側 (GUI) がSIGPIPEを受けることもない。
        cat > "$sandbox/work/yad-list-stdin.txt"
        rc="\${MOCK_LIST_RC:-0}"
        if [ "\$rc" = '0' ]; then
            printf '%s\n' "\${MOCK_LIST_SELECTION:-}"
        fi
        exit "\$rc"
        ;;
    *--entry*)
        rc="\${MOCK_ENTRY_RC:-0}"
        if [ "\$rc" = '0' ]; then
            printf '%s\n' "\${MOCK_ENTRY_TEXT:-}"
        fi
        exit "\$rc"
        ;;
    *--progress*)
        : > "$sandbox/work/progress-started"
        # PR1では無限ループさせない。killはmock-kill (絶対パス経由の完全
        # モック) として提供済みだが、進捗ダイアログのモック自体は即座に
        # 終了する設計とし、バックグラウンドプロセスの残留を避ける。
        exit "\${MOCK_PROGRESS_RC:-0}"
        ;;
    *)
        for a in "\$@"; do
            case "\$a" in
                --text=*)
                    printf '%s\n' "\${a#--text=}" >> "$sandbox/work/notice.log"
                    ;;
            esac
        done
        exit "\${MOCK_NOTICE_RC:-0}"
        ;;
esac
EOF
    chmod +x "$bin/yad"
}
