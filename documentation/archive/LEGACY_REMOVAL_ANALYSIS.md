# Legacy Architecture Removal Analysis

**Date:** 2025-12-24
**Version:** 0.22.0
**Target Removal:** v0.24.0

## Executive Summary

The legacy monolithic `lib/showoff.rb` (2,018 lines) can be removed, but **3 CLI commands and 5 test files** currently depend on it. The new architecture is the default for `serve`, `static`, and `pdf` commands. Legacy is only loaded when `SHOWOFF_USE_LEGACY_SERVER=true`.

### Critical Blockers

1. **CLI Commands:** `info`, `validate`, `heroku` use legacy-only methods
2. **Test Suite:** 5 Test::Unit files require legacy (but 31 RSpec files test new architecture)
3. **Generated Files:** `heroku` command generates config.ru files that require legacy

---

## Dependency Analysis

### 1. Files That Require Legacy Code

| File | Line | Type | Condition |
|------|------|------|-----------|
| `bin/showoff` | 411 | Direct require | Only when `SHOWOFF_USE_LEGACY_SERVER=true` |
| `test/test_helper.rb` | 7 | Direct require | Unconditional |
| `lib/showoff_utils.rb` | 217 | Generated code | In heroku config.ru |

### 2. Methods That Depend on Legacy

#### ShowoffUtils.info (line 116-145)
```ruby
showoff = Showoff.new!
content = showoff.slides(false, true)
```
**Used by:** `showoff info` command
**Dependencies:** `Showoff.new!`, `showoff.slides()`

#### ShowoffUtils.validate (line 147-191)
```ruby
showoff = Showoff.new!(:pres_file => config)
showoff.get_code_from_slide(filename.sub('.md',''), 'all', false)
```
**Used by:** `showoff validate` command
**Dependencies:** `Showoff.new!`, `showoff.get_code_from_slide()`

#### ShowoffUtils.heroku (line 215-232)
```ruby
file.puts 'require "showoff"'
file.puts 'run Showoff.new'
```
**Used by:** `showoff heroku` command
**Dependencies:** Generates config.ru that requires legacy

#### ShowoffUtils.github (line 235-246)
```ruby
Showoff.do_static(nil)
```
**Used by:** `showoff github` command
**Note:** This actually calls `showoff_ng.rb` version (not legacy) because bin/showoff loads showoff_ng for static commands

### 3. CLI Commands Using Legacy

| Command | Method Called | Legacy Dependency |
|---------|---------------|-------------------|
| `showoff serve` | `Showoff.run!` or `Showoff::ServerAdapter.run!` | Only if `SHOWOFF_USE_LEGACY_SERVER=true` |
| `showoff info` | `ShowoffUtils.info` | ✅ YES - uses `Showoff.new!` |
| `showoff validate` | `ShowoffUtils.validate` | ✅ YES - uses `Showoff.new!` |
| `showoff heroku` | `ShowoffUtils.heroku` | ✅ YES - generates legacy config.ru |
| `showoff github` | `ShowoffUtils.github` | ❌ NO - uses showoff_ng.rb |
| `showoff static` | `Showoff.do_static` | ❌ NO - uses showoff_ng.rb |
| `showoff pdf` | `Showoff.do_static` | ❌ NO - uses showoff_ng.rb |

### 4. Test Files

#### Test::Unit Tests (LEGACY - 5 files)
All require legacy via `test/test_helper.rb`:
- `test/bare_test.rb`
- `test/basic_test.rb`
- `test/markdown_test.rb`
- `test/special_content_test.rb`
- `test/utils_test.rb`

**Status:** Currently disabled in Rakefile (lines 70-85 commented out)

#### RSpec Tests (NEW - 31 files)
All test the new architecture:
- `spec/unit/showoff/*.rb` - Core classes
- `spec/unit/showoff/server/*.rb` - Server components
- `spec/unit/showoff/compiler/*.rb` - Compilation pipeline
- `spec/integration/showoff/server/*.rb` - Integration tests

**Status:** Active, 507 examples, 0 failures

---

## Feature Parity Analysis

### Routes Comparison

**Legacy routes in showoff.rb that need verification:**
- All routes have been migrated to `lib/showoff/server.rb`
- WebSocket handling migrated to `WebSocketManager`
- Form handling migrated to `FormManager`
- Stats tracking migrated to `StatsManager`
- Feedback migrated to `FeedbackManager`

### Legacy-Only Features

After analysis, **NO unique features** found in legacy that aren't in new architecture. All routes, managers, and functionality have been ported.

### Configuration Differences

Both architectures use the same `showoff.json` configuration format. No compatibility issues identified.

---

## Removal Plan

### Phase 1: Port Remaining CLI Commands

#### 1.1 Port `showoff info` Command
**File:** `lib/showoff_utils.rb` (lines 116-145)

**Current Implementation:**
```ruby
def self.info(config, json = false)
  showoff = Showoff.new!
  content = showoff.slides(false, true)
  # ... parse and display
end
```

**Migration Strategy:**
- Use `Showoff::Presentation.new` instead of `Showoff.new!`
- Use `presentation.static` or compile slides directly
- Extract image/style/script information from compiled output

**Estimated Effort:** 2-4 hours

#### 1.2 Port `showoff validate` Command
**File:** `lib/showoff_utils.rb` (lines 147-191)

**Current Implementation:**
```ruby
def self.validate(config)
  showoff = Showoff.new!(:pres_file => config)
  showoff.get_code_from_slide(filename, 'all', false)
  # ... validate code blocks
end
```

**Migration Strategy:**
- Use `Showoff::Compiler` to parse markdown
- Extract code blocks from compiled HTML using Nokogiri
- Run validators on extracted code

**Estimated Effort:** 3-5 hours

#### 1.3 Port `showoff heroku` Command
**File:** `lib/showoff_utils.rb` (lines 215-232)

**Current Implementation:**
```ruby
file.puts 'require "showoff"'
file.puts 'run Showoff.new'
```

**Migration Strategy:**
- Generate config.ru that uses new architecture:
  ```ruby
  require 'showoff_ng'
  require 'showoff/server'
  require 'showoff/server_adapter'
  run Showoff::ServerAdapter.new
  ```

**Estimated Effort:** 1-2 hours

### Phase 2: Update or Remove Test::Unit Tests

**Options:**

**Option A: Port to RSpec (RECOMMENDED)**
- Migrate 5 test files to RSpec format
- Follow patterns in existing `spec/` files
- Estimated effort: 8-12 hours

**Option B: Delete (FASTER)**
- Tests are already disabled in Rakefile
- RSpec suite has 507 passing examples covering new architecture
- Estimated effort: 1 hour (verify coverage, delete files)

**Recommendation:** Option B - Delete. The RSpec suite provides comprehensive coverage of the new architecture.

### Phase 3: Remove Legacy Code

#### Files to Delete
```
lib/showoff.rb                    # 2,018 lines - monolithic legacy server
test/test_helper.rb               # Legacy test helper
test/bare_test.rb                 # Legacy test
test/basic_test.rb                # Legacy test
test/markdown_test.rb             # Legacy test
test/special_content_test.rb      # Legacy test
test/utils_test.rb                # Legacy test
test/fixtures/                    # Legacy test fixtures (verify not used by RSpec)
```

#### Files to Modify

**bin/showoff:**
- Remove lines 268-274 (legacy server check)
- Remove lines 271-273, 398-400 (deprecation warnings)
- Remove lines 289, 303 (`Showoff.run!` calls)
- Remove line 411 (`require 'showoff'`)
- Simplify to always use `Showoff::ServerAdapter.run!`

**lib/showoff_utils.rb:**
- Update `info()` method (lines 116-145)
- Update `validate()` method (lines 147-191)
- Update `heroku()` method (lines 215-232)
- Remove line 236 if `github()` method is deprecated

**Rakefile:**
- Remove commented-out test task (lines 70-85)

**showoff.gemspec:**
- No changes needed (already includes all lib files)

### Phase 4: Update Documentation

#### Files to Update
```
documentation/AGENTS.md           # Update architecture notes
documentation/REFACTOR.rdoc       # Mark refactor complete
documentation/USAGE.rdoc          # Remove legacy references
README.md                         # Update examples
CHANGELOG.txt                     # Document removal
```

#### Files to Create
```
documentation/MIGRATION_GUIDE_v0.24.md  # Guide for users with custom config.ru
```

---

## Risk Assessment

### High Risk
None identified. New architecture is default and well-tested.

### Medium Risk

1. **Heroku Deployments**
   - **Risk:** Existing Heroku deployments use generated config.ru with legacy code
   - **Mitigation:** Provide migration guide, update `heroku` command to generate new config.ru
   - **Impact:** Users must regenerate config.ru or manually update

2. **Custom config.ru Files**
   - **Risk:** Users with custom config.ru may use `Showoff.new` directly
   - **Mitigation:** Document migration path, provide examples
   - **Impact:** Manual update required

### Low Risk

1. **Test Coverage**
   - **Risk:** Deleting Test::Unit tests reduces coverage
   - **Mitigation:** RSpec suite has 507 examples with 100% pass rate
   - **Impact:** Minimal - new architecture is well-tested

2. **CLI Command Changes**
   - **Risk:** `info`, `validate` commands may behave differently
   - **Mitigation:** Thorough testing during port, maintain same output format
   - **Impact:** Low - internal implementation change only

---

## Recommended Action Plan

### Immediate (v0.23.0)
1. ✅ Port `showoff info` command to use new architecture
2. ✅ Port `showoff validate` command to use new architecture
3. ✅ Port `showoff heroku` command to generate new config.ru
4. ✅ Add deprecation warnings to Test::Unit tests
5. ✅ Create migration guide for custom config.ru users

### Next Release (v0.24.0)
1. ✅ Delete `lib/showoff.rb`
2. ✅ Delete `test/` directory (Test::Unit tests)
3. ✅ Simplify `bin/showoff` (remove legacy conditionals)
4. ✅ Update all documentation
5. ✅ Update CHANGELOG.txt

### Testing Checklist
- [ ] Run full RSpec suite: `rake spec`
- [ ] Test `showoff info` with various presentations
- [ ] Test `showoff validate` with code blocks
- [ ] Test `showoff heroku` config.ru generation
- [ ] Test `showoff serve` without env var
- [ ] Test `showoff static` and `showoff pdf`
- [ ] Verify generated config.ru works with new architecture
- [ ] Test Heroku deployment with new config.ru

---

## Blocking Issues

### None Identified

All dependencies can be resolved by porting 3 CLI commands and deleting unused tests.

---

## Conclusion

**The legacy architecture can be safely removed in v0.24.0** after:

1. Porting 3 CLI commands (`info`, `validate`, `heroku`) - **Est. 6-11 hours**
2. Deleting 5 Test::Unit test files - **Est. 1 hour**
3. Updating documentation - **Est. 2-3 hours**

**Total Estimated Effort:** 9-15 hours

**Benefits:**
- Remove 2,018 lines of legacy code
- Eliminate dual codepath maintenance burden
- Simplify CLI entry point
- Improve code clarity and maintainability

**Risks:** Low - New architecture is default, well-tested, and feature-complete.
