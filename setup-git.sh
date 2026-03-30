#!/data/data/com.termux/files/usr/bin/bash

echo "🚀 GitHub Auto Setup Script (Termux)"

# Ask user info
read -p "👤 Enter your Git name: " GIT_NAME
read -p "📧 Enter your Git email: " GIT_EMAIL
read -p "🌐 Enter your GitHub username: " GH_USER
read -p "📦 Enter your repo name: " REPO_NAME

# Configure git
echo "⚙️ Configuring Git..."
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"

# Initialize repo if not exists
if [ ! -d ".git" ]; then
  echo "📁 Initializing repository..."
  git init
fi

# Create .gitignore (basic)
echo "🧹 Creating .gitignore..."
cat > .gitignore <<EOL
node_modules
.env
dist
build
EOL

# Add files
echo "📦 Adding files..."
git add .

# Commit
echo "📝 Creating commit..."
git commit -m "Initial commit" 2>/dev/null

# Set branch
git branch -M main

# Setup remote
REPO_URL="https://github.com/$GH_USER/$REPO_NAME.git"

echo "🔗 Connecting to GitHub..."
git remote remove origin 2>/dev/null
git remote add origin $REPO_URL

# Push
echo "🚀 Pushing to GitHub..."
git push -u origin main

echo "✅ DONE!"
echo "👉 If asked: use GitHub username + Personal Access Token (NOT password)"
