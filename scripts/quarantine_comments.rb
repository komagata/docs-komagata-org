#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'digest'
require 'optparse'
require 'sqlite3'
require 'tempfile'
require_relative '../lib/lokka/comment_spam'

module Lokka
  class CommentQuarantine
    MODERATED = 0
    SPAM = 2

    def initialize(path, readonly: false)
      raise ArgumentError, 'Database must be an existing regular file' unless File.file?(path)

      @database_digest = Digest::SHA256.hexdigest(File.realpath(path))
      @db = SQLite3::Database.new(path, readonly: readonly)
      @db.results_as_hash = true
      @db.busy_timeout = 5000
    end

    def close
      @db.close
    end

    def snapshot
      @db.execute('SELECT * FROM comments WHERE status = ? ORDER BY id', [MODERATED]).filter_map do |row|
        next unless CommentSpam.spam?(name: row['name'], homepage: row['homepage'], body: row['body'])

        { 'id' => row['id'], 'status' => MODERATED, 'digest' => content_digest(row) }
      end
    end

    def preview(rows)
      { mode: 'dry-run', matched: rows.length,
        samples: rows.first(5).map {|row| { id: row['id'], reason: 'market-advertising' } } }
    end

    def apply(rows, backup_path)
      backup = nil
      transaction do
        eligible = eligible_rows(rows, MODERATED)
        backup = { version: 2, state: 'pending', database: @database_digest, rows: eligible }
        File.open(backup_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          write_backup(file, backup)
        end
        sync_directory(backup_path)
        update_status(eligible, from: MODERATED, to: SPAM)
      end
      finalize_backup(backup_path, backup)
      { mode: 'apply', matched: rows.length, changed: backup[:rows].length,
        skipped: rows.length - backup[:rows].length }
    end

    def restore(backup_path)
      backup = JSON.parse(File.read(backup_path))
      validate_backup!(backup)
      transition(backup['rows'], from: SPAM, to: MODERATED).merge(mode: 'restore', matched: backup['rows'].length)
    end

    private

    def write_backup(file, backup)
      file.write(JSON.generate(backup))
      file.flush
      file.fsync
    end

    def sync_directory(path)
      File.open(File.dirname(path), File::RDONLY, &:fsync)
    end

    def finalize_backup(path, backup)
      Tempfile.create(['.comment-quarantine-', '.json'], File.dirname(path)) do |file|
        write_backup(file, backup.merge(state: 'applied'))
        File.rename(file.path, path)
      end
      sync_directory(path)
    end

    def content_digest(row)
      Digest::SHA256.hexdigest(JSON.generate(row.except('status').sort.to_h))
    end

    def validate_backup!(backup)
      valid = backup.is_a?(Hash) &&
        backup.values_at('version', 'state', 'database') == [2, 'applied', @database_digest] &&
        backup['rows'].is_a?(Array) && backup['rows'].all? {|row| valid_backup_row?(row) }
      raise ArgumentError, 'Invalid backup or different database path' unless valid
    end

    def valid_backup_row?(row)
      row.is_a?(Hash) && row.keys.sort == %w[digest id status] &&
        row['id'].is_a?(Integer) && row['id'].positive? && row['status'] == MODERATED &&
        row['digest'].is_a?(String) && row['digest'].match?(/\A[0-9a-f]{64}\z/)
    end

    def transition(rows, from:, to:)
      changed = transaction do
        eligible = eligible_rows(rows, from)
        update_status(eligible, from: from, to: to)
        eligible.length
      end
      { changed: changed, skipped: rows.length - changed }
    end

    def eligible_rows(rows, status)
      rows.select do |snapshot|
        row = @db.get_first_row('SELECT * FROM comments WHERE id = ?', [snapshot['id']])
        row && row['status'] == status && content_digest(row) == snapshot['digest']
      end
    end

    def update_status(rows, from:, to:)
      rows.each do |snapshot|
        @db.execute('UPDATE comments SET status = ? WHERE id = ? AND status = ?', [to, snapshot['id'], from])
        raise SQLite3::Exception, 'Expected exactly one status transition' unless @db.changes == 1
      end
    end

    def transaction
      @db.transaction(:immediate)
      result = yield
      @db.commit
      result
    ensure
      @db.rollback if @db.transaction_active?
    end
  end

  module CommentQuarantineCLI
    def self.run(args)
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: quarantine_comments.rb --database PATH [--apply --backup PATH | --restore PATH]'
        opts.on('--database PATH') {|path| options[:database] = path }
        opts.on('--apply') { options[:apply] = true }
        opts.on('--backup PATH') {|path| options[:backup] = path }
        opts.on('--restore PATH') {|path| options[:restore] = path }
        opts.on('--help') do
          puts opts
          return 0
        end
      end
      parser.parse!(args)
      validate_options!(options, args)
      quarantine = CommentQuarantine.new(options[:database], readonly: !options[:apply] && !options[:restore])
      result = if options[:restore]
                 quarantine.restore(options[:restore])
               elsif options[:apply]
                 quarantine.apply(quarantine.snapshot, options[:backup])
               else
                 quarantine.preview(quarantine.snapshot)
               end
      puts JSON.generate(result)
      0
    rescue OptionParser::ParseError, ArgumentError, JSON::ParserError, SQLite3::Exception, SystemCallError => e
      # Do not echo SQL errors, arguments, or database content into logs.
      puts JSON.generate(error: 'Command failed; check options, database and private backup file.', type: e.class.name)
      1
    ensure
      quarantine&.close
    end

    def self.validate_options!(options, args)
      raise ArgumentError, 'Database required' unless options[:database]
      raise ArgumentError, 'Unexpected arguments' unless args.empty?

      mode = %i[apply backup restore].map {|key| options.key?(key) }
      valid_modes = [[false, false, false], [true, true, false], [false, false, true]]
      raise ArgumentError, 'Choose dry run, apply with backup, or restore' unless valid_modes.include?(mode)
    end
  end
end

exit Lokka::CommentQuarantineCLI.run(ARGV) if $PROGRAM_NAME == __FILE__
