# 🛠️ buildme

**AI-powered CLI assistant for developers.**  
Undo commands. Scaffold projects. Record terminal workflows. All from your terminal.

<!-- GIF Preview -->
<p align="center">
  <img src="docs/buildme-demo.gif" alt="buildme CLI demo" width="700"/>
</p>

## ⚡️ Features

- 🔁 `buildme undo` — Revert recent terminal or `buildme` commands
- 🚀 `buildme starter` — Initialize projects from folders or GitHub repos
- ✨ `buildme generate` — Natural-language shell command generation
- 📼 `buildme record` — Record and replay your terminal workflows
- 💾 `buildme snapshot/restore` — Save and restore directory states
- 🧠 Smart model switching (`gpt-4o-mini`, DeepSeek, local models)
- ✅ Built for speed, safety, and zero-bloat workflows

---

## 🔧 Installation

```bash
git clone https://github.com/yourusername/buildme.git
cd buildme

# Zsh setup (supports .zsh)
echo "source $PWD/buildme.plugin.zsh" >> ~/.zshrc
source ~/.zshrc
```

## 🚀 Usage

### ✨ Generate shell code with AI

```bash
buildme "create a python venv and install requests"
```

Run immediately or step-by-step:

```bash
buildme --run "install packages and write requirements.txt"
buildme --step "set up project directory and init Git"
```

### 🔁 Undo terminal actions

```bash
buildme undo
```

Optionally describe what to undo:

```bash
buildme undo "remove venv folder"
```

⸻

### 🚀 Project Starters

Create a new project from a template:

```bash
buildme starter new fastapi my-api
```

Scaffold from a GitHub repo or folder:

```bash
buildme starter init my-app https://github.com/user/repo
buildme starter init cli-tool /Users/dev/templates/cli
```

List or delete:

```bash
buildme starter list
buildme starter delete old-template
```

### 📼 Record & Replay Terminal Workflows

Record a session:

```bash
buildme record start setup-node
# do stuff in terminal...
buildme record stop
```

Replay it:

```bash
buildme record replay setup-node
buildme record replay path/to/file.sh
```

Rename or list:

```bash
buildme record rename setup-node node-env
buildme record list
```

### 💾 Snapshots & Restore

Save a full project snapshot:

```bash
buildme snapshot pre-refactor
```

List or delete:

```bash
buildme snapshot list
buildme snapshot delete pre-refactor
```

Restore snapshot:

```bash
buildme restore pre-refactor
buildme restore pre-refactor --to ./backup
buildme restore pre-refactor --overwrite
buildme restore pre-refactor --dry-run
```

### 🧠 AI Model Management

```bash
buildme model list           # Show available models
buildme model set gpt-4o     # Set your preferred model
buildme model clear          # Clear all stored API keys
buildme init                 # Interactive key setup (OpenAI, DeepSeek)
```

## 🔍 Examples

```bash
# Reverse a bad install
buildme undo

# Generate a zip-cleanup script
buildme "bash script to zip all logs older than 7 days"
```

### Scaffold a FastAPI project

```bash
buildme starter new fastapi my-api
```

### Record a React setup session

```bash
buildme record start react-setup
npm create vite@latest
npm install
buildme record stop
buildme record replay react-setup
```

### Save project before trying new changes

```bash
buildme snapshot pre-experiment
```

## 🧩 Project Structure

```bash
buildme.plugin.zsh         # Main CLI entrypoint
core/                      # Internal logic (generate, run, undo, etc.)
commands/                  # Features like snapshot, record, starter
lib/                       # Helpers and utilities
```

## 🔮 Coming Soon

```bash
	•	📤 buildme share — Export and share setup steps with your team
	•	🧠 buildme explain — Understand any terminal command or file
	•	🌐 Bash + Fish shell support
```

## 🤝 Contributing

Pull requests welcome!

```bash
git clone https://github.com/yourusername/buildme.git
cd buildme
```

## 👤 Author

Dev Paragiri
[Website](https://deveshparagiri.com) • [Twitter/X](https://x.com/deveshparagiri)

⚡ If you use buildme, tweet me your workflows — I love seeing what devs are cooking.
