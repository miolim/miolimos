# #1076: Betriebsbericht.
namespace :ops do
  desc "Taeglichen Betriebsbericht per Mail verschicken (Empfaenger: OPS_REPORT_TO oder erster Admin)"
  task daily_report: :environment do
    to = ENV["OPS_REPORT_TO"].presence || HumanActor.where(role: "admin").order(:id).first&.email
    abort "ops:daily_report: kein Empfaenger (OPS_REPORT_TO setzen oder Admin anlegen)" if to.blank?

    report = Ops::DailyReport.new
    OpsMailer.daily_report(report, to: to).deliver_now
    puts "ops:daily_report: an #{to} verschickt — #{report.subject}"
  end

  desc "Betriebsbericht auf der Konsole ausgeben, ohne ihn zu verschicken"
  task report_preview: :environment do
    report = Ops::DailyReport.new
    puts report.subject
    puts
    report.alerts.each { |a| puts "! #{a}" }
    puts if report.alerts.any?
    report.sections.each do |s|
      puts "== #{s.title}"
      s.lines.each { |l| puts "   #{l}" }
      puts
    end
  end
end
