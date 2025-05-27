# 🛠️ buildme

**AI-powered CLI assistant for developers.**  
Undo commands. Generate code. Scaffold projects. All from your terminal.

<!-- GIF Preview -->
<p align="center">
  <img src="docs/buildme-demo.gif" alt="buildme CLI demo" width="700"/>
</p>
---

## ⚡️ Features

- 🔁 `buildme undo` — Revert recent terminal or `buildme` commands
- 🚀 `buildme starter` — Initialize projects from local folders or GitHub repos
- ✨ `buildme generate` — Generate code snippets or templates with natural language
- 🧠 Smart detection of GitHub URLs, repo shorthand, and local directories
- ✅ Designed for speed, safety, and terminal-native workflows

---

## 🔧 Installation

```bash
# Clone the repo
git clone https://github.com/yourusername/buildme.git
cd buildme

# Make it executable (ZSH example)
chmod +x buildme.zsh
echo "source $PWD/buildme.zsh" >> ~/.zshrc
source ~/.zshrc
```
✅ Supports Zsh. Bash and Fish coming soon.

---

## 🚀 Usage

### 🧠 Undo your last action

```bash
buildme undo
```

### 🎬 Scaffold a project from a repo or folder
```bash
buildme starter init my-app username/repo
buildme starter init my-app /path/to/project
buildme starter init my-app https://github.com/username/repo
```

Optional: add instructions to guide setup
```bash
buildme starter init cli-app username/repo --instructions="Focus on CLI structure only"
```
### ✨ Generate a code snippet
```bash
buildme generate "a python script that fetches weather data using OpenWeatherMap API"

buildme generate "a python script that fetches weather data using OpenWeatherMap API"
```
---

### 🔍 Examples

```bash
# Undo a pip install
buildme undo

# Start a new CLI project from a local folder
buildme starter init cool-cli /Users/dev/cli-template

# Clone and scaffold from GitHub
buildme starter init flask-api devparagiri/flask-api-template

# Generate a shell script that zips files in a folder
buildme generate "bash script to zip all files in ./logs older than 7 days"

```
---

### 🔮 Coming Soon
	•	🎥 buildme record — Log and replay terminal workflows
	•	📤 buildme share — Export and share setup steps with your team
	•	🧠 buildme explain — Understand any terminal command or file
	•	💾 buildme snapshot/restore — Save and restore project states
---

### 🤝 Contributing
Pull requests are welcome! For major changes, please open an issue first.

To contribute:  
```bash
git clone https://github.com/yourusername/buildme.git
cd buildme
# Hack away
```

### 📂 Project Structure
```bash
buildme.zsh           # Main CLI integration
buildme_starter.zsh   # Starter template logic
buildme_generate.zsh  # Code generation logic
buildme_undo.zsh      # Undo functionality
buildme_history.zsh   # Terminal history tracking
```

### 📜 License
```bash
This project is licensed under the MIT License.
```

### 📣 Author

Dev Paragiri
Twitter/X | Website

⚡ If you use buildme, tweet me your workflows — I love seeing what devs are cooking.

