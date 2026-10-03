# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require 'json'
require 'open3'
require 'sqlite3'
require_relative '../../scripts/quarantine_comments'

class CommentQuarantineTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('comment-quarantine-test')
    @path = File.join(@dir, 'comments.sqlite3')
    @backup = File.join(@dir, 'backup.json')
    @db = SQLite3::Database.new(@path)
    @db.execute('CREATE TABLE comments (id INTEGER PRIMARY KEY, status INTEGER, name TEXT, email TEXT,
      homepage TEXT, body TEXT, entry_id INTEGER, created_at TEXT, updated_at TEXT)')
    insert(1, 0, 'Torzon darknet market https://sites.google.com/view/torzon')
    insert(2, 1, 'Torzon https://darknetaccess.com/')
    insert(3, 0, '参考になりました https://example.org/')
    insert(4, 0, 'darknet research https://example.org/paper')
    @quarantine = Lokka::CommentQuarantine.new(@path)
  end

  def teardown
    @quarantine.close
    @db.close
    FileUtils.remove_entry(@dir)
  end

  def test_cli_defaults_to_redacted_dry_run_without_mutation
    output = cli('--database', @path)
    assert_equal 'dry-run', output['mode']
    assert_equal 1, output['matched']
    assert_equal [{ 'id' => 1, 'reason' => 'market-advertising' }], output['samples']
    refute_includes output.to_json, 'private@example.org'
    refute_includes output.to_json, 'sites.google.com'
    assert_equal [0, 1, 0, 0], statuses
    refute File.exist?(@backup)
  end

  def test_cli_apply_restore_and_repeat_are_safe
    output = cli('--database', @path, '--apply', '--backup', @backup)
    assert_equal 1, output['changed']
    assert_equal [2, 1, 0, 0], statuses
    assert_equal 0o600, File.stat(@backup).mode & 0o777
    backup = JSON.parse(File.read(@backup))
    assert_equal 2, backup['version']
    assert_equal 'applied', backup['state']
    assert_equal %w[digest id status], backup['rows'].first.keys.sort
    refute_includes backup.to_json, 'private@example.org'
    refute_includes backup.to_json, 'Torzon'

    assert_equal 0, cli('--database', @path, '--apply', '--backup', File.join(@dir, 'repeat.json'))['changed']
    assert_equal 1, cli('--database', @path, '--restore', @backup)['changed']
    assert_equal [0, 1, 0, 0], statuses
    assert_equal 0, cli('--database', @path, '--restore', @backup)['changed']
  end

  def test_apply_uses_fixed_snapshot_and_skips_content_and_status_changes
    insert(5, 0, 'Torzon https://example.org/')
    snapshot = @quarantine.snapshot
    @db.execute('UPDATE comments SET body = ? WHERE id = ?', ['Edited legitimate comment', 1])
    @db.execute('UPDATE comments SET status = ? WHERE id = ?', [1, 5])
    insert(6, 0, 'Torzon https://example.org/new')
    result = @quarantine.apply(snapshot, @backup)
    assert_equal 0, result[:changed]
    assert_equal 2, result[:skipped]
    assert_equal 0, @db.get_first_value('SELECT status FROM comments WHERE id = 6')
  end

  def test_restore_preserves_later_edits_to_any_column_and_status
    insert(5, 0, 'Torzon https://example.org/')
    insert(6, 0, 'Torzon https://example.org/')
    @quarantine.apply(@quarantine.snapshot, @backup)
    @db.execute('UPDATE comments SET email = ? WHERE id = ?', ['changed@example.org', 1])
    @db.execute('UPDATE comments SET status = ? WHERE id = ?', [1, 5])
    @db.execute('UPDATE comments SET updated_at = ? WHERE id = ?', ['later', 6])
    result = @quarantine.restore(@backup)
    assert_equal 0, result[:changed]
    assert_equal 3, result[:skipped]
    assert_equal 2, @db.get_first_value('SELECT status FROM comments WHERE id = 1')
  end

  def test_restore_never_changes_a_row_skipped_by_apply_after_concurrent_spam_classification
    snapshot = @quarantine.snapshot
    @db.execute('UPDATE comments SET status = 2 WHERE id = 1')

    assert_equal({ mode: 'apply', matched: 1, changed: 0, skipped: 1 }, @quarantine.apply(snapshot, @backup))
    assert_equal({ mode: 'restore', matched: 0, changed: 0, skipped: 0 }, @quarantine.restore(@backup))
    assert_equal 2, @db.get_first_value('SELECT status FROM comments WHERE id = 1')
    assert_empty JSON.parse(File.read(@backup))['rows']
  end

  def test_backup_contains_only_rows_actually_changed_by_apply
    insert(5, 0, 'Torzon https://example.org/')
    insert(6, 0, 'Torzon https://example.org/')
    snapshot = @quarantine.snapshot
    @db.execute('UPDATE comments SET status = 2 WHERE id = 5')
    @db.execute('UPDATE comments SET body = ? WHERE id = 6', ['Edited legitimate comment'])

    assert_equal({ mode: 'apply', matched: 3, changed: 1, skipped: 2 }, @quarantine.apply(snapshot, @backup))
    assert_equal [snapshot.first], JSON.parse(File.read(@backup))['rows']
    assert_equal({ mode: 'restore', matched: 1, changed: 1, skipped: 0 }, @quarantine.restore(@backup))
    assert_equal [0, 1, 0, 0, 2, 0], statuses
  end

  def test_existing_backup_is_never_overwritten_and_no_rows_change
    File.write(@backup, 'existing')
    assert_raises(Errno::EEXIST) { @quarantine.apply(@quarantine.snapshot, @backup) }
    assert_equal [0, 1, 0, 0], statuses
    assert_equal 'existing', File.read(@backup)
  end

  def test_private_pending_backup_is_durable_under_write_lock_before_any_update
    connection = @quarantine.instance_variable_get(:@db)
    @db.busy_timeout = 1
    connection.create_function('inspect_backup', 0) do |function|
      backup = JSON.parse(File.read(@backup))
      assert_equal 'pending', backup['state']
      assert_equal [1], backup['rows'].map {|row| row['id'] }
      assert_equal 0o600, File.stat(@backup).mode & 0o777
      assert_raises(SQLite3::BusyException) { @db.execute('BEGIN IMMEDIATE') }
      function.result = 1
    end
    @db.execute('CREATE TRIGGER inspect_backup BEFORE UPDATE ON comments BEGIN SELECT inspect_backup(); END')

    assert_equal 1, @quarantine.apply(@quarantine.snapshot, @backup)[:changed]
  end

  def test_backup_fsync_failure_prevents_database_mutation
    original_open = File.method(:open)
    failing_open = lambda do |*args, &block|
      original_open.call(*args) do |file|
        file.define_singleton_method(:fsync) { raise Errno::EIO }
        block.call(file)
      end
    end
    File.stub(:open, failing_open) do
      assert_raises(Errno::EIO) { @quarantine.apply(@quarantine.snapshot, @backup) }
    end
    assert_equal [0, 1, 0, 0], statuses
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
  end

  def test_update_failure_rolls_back_all_changes_and_leaves_non_restorable_backup
    insert(5, 0, 'Torzon https://example.org/')
    @db.execute("CREATE TRIGGER refuse_update BEFORE UPDATE ON comments WHEN NEW.id = 5
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END")

    assert_raises(SQLite3::ConstraintException) { @quarantine.apply(@quarantine.snapshot, @backup) }
    assert_equal [0, 1, 0, 0, 0], statuses
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
  end

  def test_ignored_update_cannot_produce_a_successful_backup
    @db.execute('CREATE TRIGGER ignore_update BEFORE UPDATE ON comments BEGIN SELECT RAISE(IGNORE); END')

    assert_raises(SQLite3::Exception) { @quarantine.apply(@quarantine.snapshot, @backup) }
    assert_equal [0, 1, 0, 0], statuses
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
  end

  def test_commit_failure_rolls_back_and_leaves_non_restorable_backup
    connection = @quarantine.instance_variable_get(:@db)
    connection.busy_timeout = 1
    @db.transaction(:deferred) do
      statuses # Hold a shared read lock that prevents the writer from committing.
      assert_raises(SQLite3::BusyException) { @quarantine.apply(@quarantine.snapshot, @backup) }
    end

    refute connection.transaction_active?
    assert_equal [0, 1, 0, 0], statuses
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
  end

  def test_finalization_failure_retains_pending_backup_after_commit
    File.stub(:rename, ->(*) { raise Errno::EIO }) do
      assert_raises(Errno::EIO) { @quarantine.apply(@quarantine.snapshot, @backup) }
    end

    assert_equal [2, 1, 0, 0], statuses
    assert_equal 'pending', JSON.parse(File.read(@backup))['state']
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
  end

  def test_finalization_fsync_failure_keeps_pending_file
    original_create = Tempfile.method(:create)
    failing_create = lambda do |*args, &block|
      original_create.call(*args) do |file|
        file.define_singleton_method(:fsync) { raise Errno::EIO }
        block.call(file)
      end
    end
    Tempfile.stub(:create, failing_create) do
      assert_raises(Errno::EIO) { @quarantine.apply(@quarantine.snapshot, @backup) }
    end

    assert_equal [2, 1, 0, 0], statuses
    assert_equal 'pending', JSON.parse(File.read(@backup))['state']
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
  end

  def test_pending_directory_fsync_failure_prevents_database_mutation
    fail_directory_sync(1) do
      assert_raises(Errno::EIO) { @quarantine.apply(@quarantine.snapshot, @backup) }
    end

    assert_equal [0, 1, 0, 0], statuses
    assert_equal 'pending', JSON.parse(File.read(@backup))['state']
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
  end

  def test_final_directory_fsync_failure_has_only_committed_rows_in_applied_backup
    fail_directory_sync(2) do
      assert_raises(Errno::EIO) { @quarantine.apply(@quarantine.snapshot, @backup) }
    end

    assert_equal [2, 1, 0, 0], statuses
    backup = JSON.parse(File.read(@backup))
    assert_equal 'applied', backup['state']
    assert_equal [1], backup['rows'].map {|row| row['id'] }
    assert_equal 1, @quarantine.restore(@backup)[:changed]
  end

  def test_process_death_before_commit_rolls_back_and_leaves_pending_backup
    crash_apply('before')

    assert_equal [0, 1, 0, 0], statuses
    assert_equal 'pending', JSON.parse(File.read(@backup))['state']
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
  end

  def test_process_death_after_commit_leaves_quarantined_rows_and_pending_backup
    crash_apply('after')

    assert_equal [2, 1, 0, 0], statuses
    assert_equal 'pending', JSON.parse(File.read(@backup))['state']
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
  end

  def test_restore_rejects_pending_legacy_and_incomplete_backups
    @quarantine.apply(@quarantine.snapshot, @backup)
    backup = JSON.parse(File.read(@backup))
    File.write(@backup, JSON.generate(backup.merge('state' => 'pending')))
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
    File.write(@backup, JSON.generate(backup.except('state').merge('version' => 1)))
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
    File.write(@backup, '{"version":2,')
    assert_raises(JSON::ParserError) { @quarantine.restore(@backup) }
    assert_equal [2, 1, 0, 0], statuses
  end

  def test_restore_rejects_invalid_backup_and_wrong_database
    File.write(@backup, JSON.generate(version: 1, rows: [{ id: '1; DROP TABLE comments', status: 0, digest: 'x' }]))
    assert_raises(ArgumentError) { @quarantine.restore(@backup) }
    assert_equal [0, 1, 0, 0], statuses

    @quarantine.apply(@quarantine.snapshot, File.join(@dir, 'valid.json'))
    other_path = File.join(@dir, 'other.sqlite3')
    FileUtils.cp(@path, other_path)
    other = Lokka::CommentQuarantine.new(other_path)
    assert_raises(ArgumentError) { other.restore(File.join(@dir, 'valid.json')) }
  ensure
    other&.close
  end

  def test_cli_refuses_missing_database_and_apply_without_backup
    output, status = Open3.capture2e(RbConfig.ruby, script, '--database', File.join(@dir, 'missing.sqlite3'))
    refute status.success?
    assert JSON.parse(output)['error']
    refute File.exist?(File.join(@dir, 'missing.sqlite3'))

    output, status = Open3.capture2e(RbConfig.ruby, script, '--database', @path, '--apply')
    refute status.success?
    assert JSON.parse(output)['error']
    assert_equal [0, 1, 0, 0], statuses
  end

  private

  def fail_directory_sync(nth, &operation)
    original_open = File.method(:open)
    count = 0
    failing_open = lambda do |*args, **options, &block|
      next original_open.call(*args, **options, &block) unless File.directory?(args.first)

      original_open.call(*args, **options) do |file|
        count += 1
        file.define_singleton_method(:fsync) { raise Errno::EIO } if count == nth
        block.call(file)
      end
    end
    File.stub(:open, failing_open, &operation)
  end

  def crash_apply(phase)
    code = <<~RUBY
      quarantine = Lokka::CommentQuarantine.new(ARGV.fetch(0))
      connection = quarantine.instance_variable_get(:@db)
      original_commit = connection.method(:commit)
      connection.define_singleton_method(:commit) do
        original_commit.call if ARGV.fetch(2) == 'after'
        Process.kill('KILL', Process.pid)
      end
      quarantine.apply(quarantine.snapshot, ARGV.fetch(1))
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, '-r', script, '-e', code, @path, @backup, phase)
    assert status.signaled?, output
    assert_equal Signal.list.fetch('KILL'), status.termsig
  end

  def insert(id, status, body)
    @db.execute('INSERT INTO comments (id, status, name, email, body) VALUES (?, ?, ?, ?, ?)',
                [id, status, 'Reader', 'private@example.org', body])
  end

  def statuses
    @db.execute('SELECT status FROM comments ORDER BY id').flatten
  end

  def script
    File.expand_path('../../scripts/quarantine_comments.rb', __dir__)
  end

  def cli(*)
    output, status = Open3.capture2e(RbConfig.ruby, script, *)
    assert status.success?, output
    JSON.parse(output)
  end
end
