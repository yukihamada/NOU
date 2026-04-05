[Setup]
AppName=NOU
AppVersion=0.1.0
AppPublisher=EnablerDAO
AppPublisherURL=https://github.com/yukihamada/NOU
AppSupportURL=https://github.com/yukihamada/NOU/issues
DefaultDirName={autopf}\NOU
DefaultGroupName=NOU
OutputBaseFilename=NOU-Setup-Windows
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=icon.ico
UninstallDisplayIcon={app}\nou-server.exe
PrivilegesRequired=lowest

[Files]
Source: "nou-server.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\NOU ローカルAI"; Filename: "{app}\nou-server.exe"
Name: "{group}\NOU アンインストール"; Filename: "{uninstallexe}"
Name: "{commondesktop}\NOU"; Filename: "{app}\nou-server.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "デスクトップにショートカットを作成"; GroupDescription: "追加タスク"
Name: "autostart"; Description: "Windows 起動時に自動的に開始"; GroupDescription: "追加タスク"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "NOU"; ValueData: """{app}\nou-server.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\nou-server.exe"; Description: "NOU を起動する"; Flags: nowait postinstall skipifsilent
Filename: "https://ollama.com/download"; Description: "Ollama をインストールする (必要)"; Flags: shellexec postinstall skipifsilent unchecked

[UninstallRun]
Filename: "taskkill"; Parameters: "/F /IM nou-server.exe"; Flags: runhidden

[Messages]
WelcomeLabel1=NOU ローカルAI セットアップへようこそ
WelcomeLabel2=このウィザードは NOU をあなたのコンピューターにインストールします。%n%nNOU は AI モデルをローカルで動かし、Claude Code・Cursor・Aider などのツールをクラウドなしで使えるようにします。
FinishedHeadingLabel=NOU のインストールが完了しました
FinishedLabel=NOU がインストールされました。%n%n次のステップ:%n1. Ollama をインストール (ollama.com/download)%n2. ollama pull gemma3:4b%n3. http://localhost:4001 を開く
