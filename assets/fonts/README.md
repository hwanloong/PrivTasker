# 字体目录（需自行准备）

**这个目录里的字体文件不随仓库分发。**

本目录在 `.gitignore` 中被排除。请按下文自行准备，否则构建会因为找不到字体资源而失败。

## 需要哪些文件

```
assets/fonts/
├── times.ttf         Times New Roman Regular
├── timesbd.ttf       Times New Roman Bold
├── timesi.ttf        Times New Roman Italic
├── timesbi.ttf       Times New Roman Bold Italic
├── simsun.ttf        宋体（从 simsun.ttc 抽出的独立 TTF）
├── consola.ttf       Consolas Regular
├── consolab.ttf      Consolas Bold
└── consolai.ttf      Consolas Italic
```

## 为什么要自己准备

这三款字体都是**商业专有字体**：

| 字体 | 权利人 |
|---|---|
| Times New Roman | Monotype |
| 宋体 SimSun | 中易中标 / Microsoft |
| Consolas | Microsoft |

它们随 Windows 授权给**本机使用者**，但授权范围**不包括再分发**。
把它们提交到公开仓库或公开分发带字体的构建产物都属于侵权。

在你自己的机器上使用属于正常的系统授权范围。

## 准备方法

```powershell
cd assets/fonts

# Times New Roman 与 Consolas：单文件，直接复制
Copy-Item C:\Windows\Fonts\times.ttf    .
Copy-Item C:\Windows\Fonts\timesbd.ttf  .
Copy-Item C:\Windows\Fonts\timesi.ttf   .
Copy-Item C:\Windows\Fonts\timesbi.ttf  .
Copy-Item C:\Windows\Fonts\consola.ttf  .
Copy-Item C:\Windows\Fonts\consolab.ttf .
Copy-Item C:\Windows\Fonts\consolai.ttf .

# 宋体：Windows 上是 TrueType 集合（.ttc），需要抽成独立 TTF
Copy-Item C:\Windows\Fonts\simsun.ttc .
dart ..\..\tools\extract_ttc.dart simsun.ttc simsun.ttf 0
Remove-Item simsun.ttc
```

### 校验

```powershell
Get-ChildItem | Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB)}}
```

`simsun.ttf` 应该是 **约 17.5 MB**。前 4 个字节应为 `00 01 00 00`（合法 sfnt 头）：

```powershell
Format-Hex simsun.ttf -Count 4
```

也可以先看集合里有哪些字体：

```powershell
dart ..\..\tools\extract_ttc.dart simsun.ttc --list
```

应该输出两个：`[0] family="SimSun"` 和 `[1] family="NSimSun"`。取索引 0。

## 为什么宋体要抽出来

`simsun.ttc` 是 TrueType **集合**文件（一个文件装多个字体），而 Flutter 对 `.ttc`
的支持不明确。最坏的情况是**加载失败后静默回退**到系统默认字体 ——
界面上中文会变成黑体，而这种问题在手机上不容易当场发现。

抽成独立的 `.ttf` 就消除了这个不确定性。细节见 `tools/extract_ttc.dart` 的注释。

## 想用开源字体替代

如果打算公开分发带字体的构建产物，需要换成可自由分发的字体。推荐：

| 用途 | 替代 | 许可 |
|---|---|---|
| 中文宋体/明朝体 | [思源宋体 Source Han Serif](https://github.com/adobe-fonts/source-han-serif) | SIL OFL 1.1 |
| 英文衬线 | [EB Garamond](https://github.com/octaviopardo/EBGaramond12) | SIL OFL 1.1 |
| 等宽 | [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) | SIL OFL 1.1 |

换字体只需改两处：

1. `pubspec.yaml` 的 `fonts:` 段（资源路径与家族名）
2. `lib/theme/app_theme.dart` 的 `AppFonts.latin` / `cjk` / `mono`

全项目只有这两处引用字体名。
