# Script Maintenance Patterns

## Glyph Variable Standardization (2025-07-18)

### Issue: Inconsistent Glyph Usage
The setup-k3s-arc.sh script had inconsistent glyph (emoji) usage:

1. **Partial variable definitions**: Only 7 glyphs defined as variables (lines 22-28)
2. **Hardcoded instances**: 50+ instances throughout the script used hardcoded glyphs
3. **Maintenance problem**: Changing a glyph required manual updates in multiple locations

### Root Cause Analysis
```bash
# Original variable definitions (incomplete)
CHECK="✅"
CROSS="❌"
WARN="⚠️"
INFO="ℹ️"
ROCKET="🚀"
GEAR="⚙️"
CLOUD="☁️"

# But throughout the script:
echo "🔧 Applying DNS fix..."           # Hardcoded
log "✅ DNS working"                    # Hardcoded
verbose_log "⏳ Waiting..."             # Hardcoded
```

### Solution: Complete Glyph Standardization

#### Extended Variable Definitions
**Added 17 new glyph variables** to create comprehensive coverage:
```bash
# Original definitions (lines 22-28)
CHECK="✅"
CROSS="❌"
WARN="⚠️"
INFO="ℹ️"
ROCKET="🚀"
GEAR="⚙️"
CLOUD="☁️"

# Extended definitions (lines 29-45)
LOCK="🔐"
CLOCK="🕒"
WRENCH="🔧"
REFRESH="🔄"
HOURGLASS="⏳"
TEST="🧪"
COMPUTER="🖥️"
SHIP="🚢"
LINK="🔗"
BOOKS="📚"
GLOBE="🌐"
CHART="📊"
MEMO="📝"
CLIPBOARD="📋"
CELEBRATION="🎉"
LIGHTBULB="💡"
FOLDER="📁"
```

#### Systematic Replacement Process
**Replaced 50+ hardcoded instances** with variable references:

```bash
# Before
echo "🔧 Applying DNS fix..."
log "✅ DNS working"
verbose_log "⏳ Waiting for stabilization..."
show_status "🔄 Restarting services..."

# After
echo "${WRENCH} Applying DNS fix..."
log "${CHECK} DNS working"
verbose_log "${HOURGLASS} Waiting for stabilization..."
show_status "${REFRESH} Restarting services..."
```

### Technical Implementation

#### Variable Syntax Standard
- **Format**: Use `${VARIABLE_NAME}` for all references
- **Location**: All glyph variables defined at script top (lines 22-45)
- **Naming**: Descriptive names that clarify intent vs raw emojis

#### Search Methodology
```bash
# Used to locate all hardcoded glyphs
grep -n "🔧\|✅\|❌\|⚠️\|🚀\|⚙️\|☁️\|🔐\|🕒\|🔄\|⏳\|🧪\|🖥️\|🚢\|🔗\|📚\|🌐\|📊\|📝\|📋\|🎉\|💡\|📁" setup-k3s-arc.sh

# Verification: Final search confirmed zero remaining hardcoded instances
grep -P "[\x{1F300}-\x{1F9FF}]" setup-k3s-arc.sh | grep -v "^[[:space:]]*[A-Z_]*=\""
```

#### Coverage Areas Updated
- **Logging functions**: `log()`, `verbose_log()`, `warn()`, `error()`
- **Status displays**: `show_status()` function calls
- **DNS fix messages**: All DNS-related output
- **Progress indicators**: Step completion markers
- **Error handling**: Error and warning messages

### Benefits Achieved

#### 1. Single Source of Truth
- All glyphs centralized in lines 22-45
- No scattered definitions throughout script
- Easy to see all used glyphs at a glance

#### 2. Easy Maintenance
```bash
# Change one variable to update entire script
WRENCH="🔨"  # Changes all wrench references instantly
```

#### 3. Consistency Guarantee
- No risk of glyph mismatches between similar contexts
- Systematic usage patterns
- IDE autocomplete support

#### 4. Better Readability
```bash
# Variable names clarify intent
echo "${WRENCH} Applying fix..."     # Clear: tool/fixing context
echo "${CHECK} Operation complete"   # Clear: success context
echo "${HOURGLASS} Please wait..."   # Clear: waiting context

# vs hardcoded (unclear intent)
echo "🔧 Applying fix..."
echo "✅ Operation complete"  
echo "⏳ Please wait..."
```

## Code Standards

### Variable Naming Conventions
```bash
# Glyph variables: ALL_CAPS with descriptive names
CHECK="✅"
WRENCH="🔧"
HOURGLASS="⏳"

# Configuration variables: ALL_CAPS
DNS_SERVERS="1.1.1.1 1.0.0.1"
MAX_WAIT_TIME=300

# Local variables: snake_case
local pod_count=0
local dns_status="unknown"
```

### Function Organization
```bash
# Utility functions at top
log() { ... }
verbose_log() { ... }
error() { ... }

# Core functions in logical order
setup_time_sync() { ... }
install_k3s() { ... }
connect_to_arc() { ... }

# Helper functions after their usage context
apply_dns_fix() { ... }
test_dns_connectivity() { ... }
```

### Message Format Standards
```bash
# Main steps: [n/total] format
echo "[${STEP}/${TOTAL_STEPS}] ${action_description}..."

# Substeps: Indented with glyph
echo "     ${WRENCH} ${substep_description}"
echo "       ${CHECK} ${status_message}"

# Verbose details: No visual hierarchy
verbose_log "${technical_detail}"
```

### Error Handling Patterns
```bash
# Standard error format
error() {
    echo "${CROSS} ERROR: $1" >&2
    [[ -n "$2" ]] && verbose_log "Details: $2"
    return 1
}

# Warning format
warn() {
    echo "${WARN} WARNING: $1" >&2
}

# Success format
success() {
    echo "${CHECK} $1"
}
```

## Pattern for Future Development

### Adding New Glyphs
```bash
# 1. Add to variable definitions (lines 22-45)
NEW_GLYPH="🔥"

# 2. Use throughout script with variables
echo "${NEW_GLYPH} Message here"
log "${NEW_GLYPH} Status update"
verbose_log "${NEW_GLYPH} Technical detail"

# 3. Verify no hardcoded instances
grep "🔥" setup-k3s-arc.sh | grep -v "NEW_GLYPH="
```

### Message Consistency
```bash
# DNS fix messages - standardized pattern
echo "${WRENCH} Arc agents need DNS fix..."
echo "${WRENCH} Applying DNS fix for Arc connectivity..."
echo "${CHECK} Cluster DNS now working correctly"
echo "${REFRESH} Restarting Arc agents..."
echo "${CHECK} DNS fix completed successfully"
```

### Code Review Checklist
- [ ] All new glyphs defined as variables
- [ ] No hardcoded emoji in messages
- [ ] Consistent indentation for substeps
- [ ] Proper verbose_log() usage for technical details
- [ ] Error messages include ${CROSS} prefix
- [ ] Success messages include ${CHECK} prefix

## Integration Benefits

### DNS Fix Integration
The glyph standardization ensures consistent messaging in DNS fixes:
```bash
# All DNS-related messages use standardized glyphs
echo "${WRENCH} Arc agents need DNS fix..."
echo "${WRENCH} Applying DNS fix for Arc connectivity..."
echo "${CHECK} Cluster DNS now working correctly"
echo "${REFRESH} Restarting Arc agents..."
echo "${CHECK} DNS fix completed successfully"
```

### User Experience Enhancement
- **Visual consistency**: Same glyphs always mean the same thing
- **Professional appearance**: No random emoji variations
- **Easier scanning**: Users learn glyph meanings quickly
- **Maintainable**: Easy to update visual style project-wide

### Developer Benefits
- **IDE support**: Variables provide autocomplete
- **Refactoring safety**: Change definition updates all uses
- **Code review**: Easy to spot hardcoded glyphs
- **Documentation**: Variable names self-document intent

## Glyph Standardization Applied to Build Scripts (2025-07-30)

### Extension to build-k3s-arc-offline-install-bundle.sh
**Context**: During Step 3 of offline implementation, initial build script contained hardcoded glyphs despite using proper variable definitions at the top.

**Issue Identified**:
- Script defined all glyph variables correctly at lines 31-57
- Generated component installer script contained hardcoded `✅` and `❌` instead of `${CHECK}` and `${CROSS}`
- Inconsistent with established [`setup-k3s-arc.sh`](setup-k3s-arc.sh:22-47) patterns

**Solution Applied**:
```bash
# BEFORE (in generated installer script)
echo "✅ Helm installed"
echo "❌ Helm binary not found"

# AFTER (using variable references)
echo "${CHECK} Helm installed"
echo "${CROSS} Helm binary not found"
```

**Key Learning**: Generated scripts must also follow glyph variable standards
- When scripts generate other scripts, ensure variable substitution not literal text
- Generated installers should inherit variable patterns from parent script
- Maintain consistency across all script artifacts

### Build Script Quality Standards
**All scripts in the offline implementation must**:
- ✅ Define all glyphs as variables at script top (lines 22-57 pattern)
- ✅ Use `${VARIABLE}` syntax for all glyph references
- ✅ Apply standards to any generated scripts or sub-components
- ✅ Follow [`setup-k3s-arc.sh`](setup-k3s-arc.sh:22-47) exact variable names and patterns
- ✅ Verify no hardcoded glyphs remain using search patterns

**Pattern Verification Command**:
```bash
# Search for any hardcoded glyphs (should return only variable definitions)
grep -P "[\x{1F300}-\x{1F9FF}]" script.sh | grep -v "^[[:space:]]*[A-Z_]*=\""
```

### Generated Script Standards
When creating installer scripts or sub-components:
```bash
# CORRECT - Pass variables through to generated scripts
cat > "$scripts_dir/install-components.sh" << 'EOF'
#!/bin/bash
CHECK="✅"
CROSS="❌"

echo "${CHECK} Component installed"
echo "${CROSS} Component failed"
EOF

# Or reference parent script variables in generation context
echo "echo \"\${CHECK} Component installed\"" > generated_script.sh
```

---

*Pattern established: 2025-07-18*
*Extended for build scripts: 2025-07-30*
*All future script modifications should follow these standards*