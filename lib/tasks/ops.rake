# #1076: Betriebsbericht.
namespace :ops do
  desc "Taeglichen Betriebsbericht per Mail verschicken (Empfaenger: OPS_REPORT_TO oder erster Admin)"
  task daily_report: :environment do
    admin = HumanActor.where(role: "admin").order(:id).first
    to = ENV["OPS_REPORT_TO"].presence || admin&.email
    abort "ops:daily_report: kein Empfaenger (OPS_REPORT_TO setzen oder Admin anlegen)" if to.blank?

    report = Ops::DailyReport.new

    begin
      OpsMailer.daily_report(report, to: to).deliver_now
      puts "ops:daily_report: an #{to} verschickt — #{report.subject}"
    rescue StandardError => e
      # ERSATZWEG. Ein Ueberwachungssystem, dessen einziger Kanal kaputt ist,
      # ueberwacht nichts mehr — und genau dieser Fall lag am 21.07.2026 vor:
      # die Google-Credential war zehn Tage abgelaufen, ohne dass es jemand
      # merkte. Kommt die Mail nicht durch, wird der Bericht dort abgelegt, wo
      # Hans ohnehin taeglich hinschaut. Nur im Fehlerfall — sonst waechst der
      # Wissensbestand taeglich zu.
      warn "ops:daily_report: Mailversand fehlgeschlagen (#{e.class}: #{e.message})"
      Ops::ReportFallback.new(report, actor: admin, reason: "#{e.class}: #{e.message}").deliver!
      puts "ops:daily_report: als Wissenselement abgelegt — #{report.subject}"
      exit 1
    end
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
