# #203 Phase E.5: AuditLog-Pattern als Concern. Models koennen audited
# werden via:
#
#   class Task < ApplicationRecord
#     include Auditable
#     audited %w[status title assignee_id priority due_date commitment]
#   end
#
# Schreibt AuditLogs in den 3 Lifecycle-Phasen — aber nur, wenn
# `Current.actor` gesetzt ist (Seeds, Background-Jobs ohne Actor →
# keine Noise-Eintraege).
module Auditable
  extend ActiveSupport::Concern

  included do
    class_attribute :audited_attrs, instance_writer: false, default: []
    after_create  :_log_audit_created
    after_update  :_log_audit_updated
    after_destroy :_log_audit_destroyed
  end

  class_methods do
    def audited(attrs)
      self.audited_attrs = Array(attrs).map(&:to_s).freeze
    end
  end

  private

  def _log_audit_created
    return unless Current.actor
    fields = {}
    fields["title"]  = [nil, title]  if respond_to?(:title)
    fields["status"] = [nil, status] if respond_to?(:status)
    AuditLog.create!(actor: Current.actor, action: "created",
                     auditable: self, changes_data: fields)
  end

  def _log_audit_updated
    return unless Current.actor
    relevant = saved_changes.slice(*self.class.audited_attrs)
    return if relevant.empty?
    AuditLog.create!(actor: Current.actor, action: "updated",
                     auditable: self, changes_data: relevant)
  end

  def _log_audit_destroyed
    return unless Current.actor
    fields = {}
    fields["title"] = [respond_to?(:title) ? title : nil, nil]
    AuditLog.create!(actor: Current.actor, action: "destroyed",
                     auditable: self, changes_data: fields)
  end
end
