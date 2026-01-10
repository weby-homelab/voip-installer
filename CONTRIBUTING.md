# Contributing

We welcome contributions to the VoIP Installer project!

## How to Contribute

1. **Fork the repository** to your own GitHub account.
2. **Create a new branch** for your feature or bugfix:
   ```bash
   git checkout -b feature/my-new-feature
   ```
3. **Commit your changes** with clear messages:
   ```bash
   git commit -m "Add feature X"
   ```
4. **Push to the branch**:
   ```bash
   git push origin feature/my-new-feature
   ```
5. **Open a Pull Request** against the main repository.

## Testing

Before submitting, please ensure the script syntax is correct by running the test in the `tests/` directory:

```bash
./tests/test_syntax.sh
```

## Coding Style

* Keep the script compatible with Bash 4.0+.
* Use 2 spaces for indentation in `install.sh`.
* Ensure all variables are quoted.
* Add comments for complex logic.
