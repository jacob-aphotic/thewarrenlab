#!/usr/bin/env python3
"""
gen-pdfs.py — Lapin Logistics asset generator.

Usage:
    python3 assets/gen-pdfs.py --outdir <directory>

Outputs (always written; overwrites any existing files):
    IT_orientation.pdf
    carrot_quality_standards.pdf
    q3_logistics_review.pdf

Dependencies:
    pip install reportlab

Exit codes:
    0  success
    1  argument/dependency error
"""

import argparse
import os
import sys


def parse_args():
    p = argparse.ArgumentParser(description="Generate Lapin Logistics corporate PDF documents")
    p.add_argument("--outdir", required=True, help="Directory to write generated files into")
    return p.parse_args()


# ---------------------------------------------------------------------------
# Shared style helpers
# ---------------------------------------------------------------------------

def _build_styles():
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.enums import TA_LEFT, TA_CENTER
    from reportlab.lib import colors

    styles = getSampleStyleSheet()

    styles.add(ParagraphStyle(
        name="DocTitle",
        fontSize=16,
        leading=20,
        spaceBefore=0,
        spaceAfter=14,
        fontName="Helvetica-Bold",
        alignment=TA_CENTER,
    ))
    styles.add(ParagraphStyle(
        name="DocSubtitle",
        fontSize=10,
        leading=13,
        spaceBefore=0,
        spaceAfter=18,
        fontName="Helvetica",
        alignment=TA_CENTER,
        textColor=colors.HexColor("#555555"),
    ))
    styles.add(ParagraphStyle(
        name="SectionHeading",
        fontSize=12,
        leading=16,
        spaceBefore=14,
        spaceAfter=4,
        fontName="Helvetica-Bold",
    ))
    styles.add(ParagraphStyle(
        name="Body",
        fontSize=10,
        leading=15,
        spaceBefore=4,
        spaceAfter=4,
        fontName="Helvetica",
    ))
    styles.add(ParagraphStyle(
        name="BodyIndent",
        fontSize=10,
        leading=15,
        spaceBefore=2,
        spaceAfter=2,
        fontName="Helvetica",
        leftIndent=20,
    ))
    styles.add(ParagraphStyle(
        name="Footer",
        fontSize=8,
        leading=11,
        spaceBefore=8,
        spaceAfter=0,
        fontName="Helvetica-Oblique",
        textColor=colors.HexColor("#888888"),
    ))

    return styles


# ---------------------------------------------------------------------------
# IT_orientation.pdf
# ---------------------------------------------------------------------------

def make_it_orientation(outdir: str) -> str:
    """
    Multi-page new-starter onboarding handbook covering HR, IT account
    provisioning, facilities and policy sections.
    """
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import cm

    path = os.path.join(outdir, "IT_orientation.pdf")

    doc = SimpleDocTemplate(
        path,
        pagesize=A4,
        leftMargin=2.5 * cm,
        rightMargin=2.5 * cm,
        topMargin=2.5 * cm,
        bottomMargin=2.5 * cm,
        title="New Starter Orientation Handbook",
        author="Lapin Logistics IT",
        subject="Human Resources — Onboarding",
    )

    styles = _build_styles()
    S = styles["SectionHeading"]
    B = styles["Body"]
    I = styles["BodyIndent"]
    F = styles["Footer"]
    T = styles["DocTitle"]
    Sub = styles["DocSubtitle"]

    story = []

    # ------------------------------------------------------------------
    # PAGE 1 — Cover / Welcome
    # ------------------------------------------------------------------
    story.append(Spacer(1, 1.5 * cm))
    story.append(Paragraph("Lapin Logistics", T))
    story.append(Paragraph("New Starter Orientation Handbook", T))
    story.append(Paragraph(
        "Confidential — Internal Use Only &nbsp;&nbsp;|&nbsp;&nbsp; "
        "Document Ref: HR-ORI-001 &nbsp;&nbsp;|&nbsp;&nbsp; Revision 4.2",
        Sub,
    ))
    story.append(Spacer(1, 0.4 * cm))

    story.append(Paragraph("Welcome to Lapin Logistics", S))
    story.append(Paragraph(
        "On behalf of the entire team, welcome aboard. Lapin Logistics has been "
        "providing temperature-controlled carrot and produce distribution across "
        "Central and Eastern Europe since 1973. We pride ourselves on our reputation "
        "for reliability, freshness, and the professional conduct of every member of "
        "our staff. This handbook sets out everything you need to know during your "
        "first weeks with us and serves as a reference for day-to-day working life "
        "at Lapin Logistics.",
        B,
    ))
    story.append(Paragraph(
        "Please read this document carefully and retain it for future reference. "
        "If you have questions that are not answered here, your line manager or a "
        "member of the People &amp; Culture team will be happy to help. You can also "
        "reach HR directly at hr@lapinlogistics.local or on the internal extension 200.",
        B,
    ))

    story.append(Paragraph("About This Document", S))
    story.append(Paragraph(
        "This handbook is issued to all new employees on or before their first working day. "
        "It covers company background, facilities, HR policies, IT account setup, "
        "acceptable use of systems, holiday and leave entitlements, health and safety "
        "obligations, and useful contacts. It is reviewed annually by People &amp; Culture "
        "in conjunction with the IT Security team.",
        B,
    ))
    story.append(Paragraph(
        "Sections covering IT access, acceptable use, and security policy are mandatory "
        "reading; you will be asked to sign a declaration on Day 1 confirming that you have "
        "read and understood them. The declaration is filed with your employment record.",
        B,
    ))

    story.append(Paragraph("Company Overview", S))
    story.append(Paragraph(
        "Lapin Logistics was founded in 1973 by Henri and Marguerite Lapin, initially "
        "operating a small cold-storage depot on the outskirts of Strasbourg. Over five "
        "decades the company has grown into one of the region's leading specialist "
        "distributors, with hub facilities in Strasbourg, Vienna, Warsaw, and Bucharest, "
        "and a fleet of over 200 refrigerated vehicles. Our client base spans wholesale "
        "grocers, supermarket chains, catering companies, and institutional kitchens across "
        "fourteen countries.",
        B,
    ))
    story.append(Paragraph(
        "Our core product remains the fresh carrot — graded, cleaned, and packed to "
        "exacting quality standards at our processing centres before onward distribution. "
        "We also handle a range of root vegetables and short-shelf-life produce under "
        "temperature-controlled conditions that meet or exceed EU food safety regulations. "
        "In recent years we have expanded into same-day urban delivery for premium grocery "
        "clients, a service that now accounts for roughly eighteen percent of group revenue.",
        B,
    ))

    story.append(PageBreak())

    # ------------------------------------------------------------------
    # PAGE 2 — Facilities & HR
    # ------------------------------------------------------------------
    story.append(Paragraph("2.  Facilities and Working Environment", S))
    story.append(Paragraph(
        "Our Strasbourg headquarters occupies a four-storey building at 14 Rue du Marché "
        "Vert, with a separate warehouse and cold-storage complex accessed from the rear "
        "car park. Visitor parking is available on the ground level; staff parking permits "
        "are issued by Facilities Management (ext. 310) and must be displayed on the "
        "dashboard at all times.",
        B,
    ))
    story.append(Paragraph(
        "The main reception is staffed from 07:30 to 18:00 Monday to Friday. Out-of-hours "
        "access requires a staff proximity card, which will be issued by Facilities on your "
        "first day after you have completed the standard identity verification process. "
        "Notify your line manager if your card is lost or stolen; it will be cancelled and "
        "reissued within one working day. There is no charge for a first replacement card; "
        "subsequent replacements attract a nominal administration fee of €15.",
        B,
    ))

    story.append(Paragraph("Catering and Break Areas", S))
    story.append(Paragraph(
        "A subsidised staff canteen operates on the second floor, serving hot meals from "
        "12:00 to 14:00 on working days. A selection of cold drinks, fruit, and snacks is "
        "available via vending machines in the ground-floor break room at all hours. "
        "Hot beverage stations are located on each office floor; staff are asked to clean "
        "the station after use and not to leave unwashed crockery overnight.",
        B,
    ))
    story.append(Paragraph(
        "The break room on the third floor contains a small library of industry periodicals "
        "and a noticeboard for internal announcements. Notices must be approved by "
        "People &amp; Culture before posting; contact pc@lapinlogistics.local.",
        B,
    ))

    story.append(Paragraph("3.  Human Resources Policies", S))
    story.append(Paragraph(
        "Lapin Logistics is committed to creating a workplace that is inclusive, respectful, "
        "and free from harassment or discrimination. All employees are expected to read and "
        "adhere to the Equal Opportunities Policy, a copy of which is available on the "
        "intranet under HR Policies &gt; Equality and Inclusion.",
        B,
    ))

    story.append(Paragraph("Probationary Period", S))
    story.append(Paragraph(
        "All new employees serve a six-month probationary period. During this time your "
        "line manager will conduct monthly one-to-one reviews to discuss progress, "
        "objectives, and any support you may need. A formal probationary review meeting "
        "will take place at the end of month six; successful completion is confirmed in "
        "writing by People &amp; Culture.",
        B,
    ))

    story.append(Paragraph("Grievance and Disciplinary Procedures", S))
    story.append(Paragraph(
        "Full details of the grievance and disciplinary procedures are set out in the "
        "Employee Handbook Supplement (document ref HR-SUP-003), available from People "
        "&amp; Culture on request or via the intranet. In summary: concerns should in "
        "the first instance be raised informally with your line manager; if unresolved, "
        "a formal written grievance may be submitted to hr@lapinlogistics.local. "
        "Lapin Logistics follows a three-stage disciplinary process — verbal warning, "
        "written warning, final written warning — except in cases of gross misconduct, "
        "where summary dismissal may apply.",
        B,
    ))

    story.append(Paragraph("Holiday and Leave Entitlements", S))
    story.append(Paragraph(
        "Full-time employees are entitled to 25 days of annual leave per calendar year in "
        "addition to public holidays observed in your country of employment. Leave is "
        "booked through the HR self-service portal; requests of up to five consecutive "
        "days require only line manager approval, while requests of six or more days must "
        "additionally be approved by the relevant department head.",
        B,
    ))
    story.append(Paragraph(
        "Carry-over of unused annual leave is permitted up to a maximum of five days, "
        "provided the carried-over days are taken before 31 March of the following year. "
        "Statutory sick leave is recorded separately from annual leave; employees absent "
        "for more than three consecutive working days due to illness must provide a medical "
        "certificate to People &amp; Culture.",
        B,
    ))

    story.append(PageBreak())

    # ------------------------------------------------------------------
    # PAGE 3 — IT Account Provisioning  <-- password buried here
    # ------------------------------------------------------------------
    story.append(Paragraph("4.  IT Account Provisioning and First Login", S))
    story.append(Paragraph(
        "Lapin Logistics operates a single-sign-on environment based on our internal "
        "Active Directory domain, lapinlogistics.local. Your network account provides "
        "access to email, shared drives, the HR self-service portal, the logistics "
        "management system (LMS), and any line-of-business applications relevant to your "
        "role. Access is granted on a least-privilege basis; your initial permission set "
        "is determined by your job profile and confirmed with your line manager before "
        "your start date.",
        B,
    ))
    story.append(Paragraph(
        "Your account is created by IT ahead of your start date using the details supplied "
        "by People &amp; Culture at the point of contract signing. The username follows "
        "the standard format firstname.lastname (e.g. a new joiner called Sarah "
        "Beaumont would have the username sarah.beaumont). If your name generates a "
        "collision with an existing account, IT will contact you before your start date "
        "to agree an alternative format.",
        B,
    ))
    story.append(Paragraph(
        "Until you set your own password at first login, your account carries the standard "
        "temporary onboarding password issued to every new starter: Carrot$tart2024. "
        "This password must be changed within 24 hours of your first login in accordance "
        "with the security policy described in Section 5. Failure to change the temporary "
        "password within the required window will result in the account being automatically "
        "locked; IT can unlock it on request via the service desk (ext. 101 or "
        "it-support@lapinlogistics.local).",
        B,
    ))
    story.append(Paragraph(
        "On your first login you will be prompted by the system to set a new password, "
        "enrol a recovery email address, and configure multi-factor authentication (MFA) "
        "using the Microsoft Authenticator app or a hardware token if one has been issued "
        "to you. The MFA enrolment guide is available at "
        "http://intranet.lapinlogistics.local/it/mfa-setup. If you encounter any difficulty "
        "during enrolment, contact the IT service desk; do not share your temporary "
        "credentials with colleagues.",
        B,
    ))
    story.append(Paragraph(
        "Email is provisioned via Microsoft Exchange and is accessible through Outlook on "
        "your workstation or via the web client at mail.lapinlogistics.local. Your "
        "corporate email address follows the format firstname.lastname@lapinlogistics.local. "
        "Distribution lists for your department will be set up by IT within two working "
        "days of your start date; contact your line manager if you believe you are missing "
        "from a required list.",
        B,
    ))

    story.append(Paragraph("Hardware and Workstation Setup", S))
    story.append(Paragraph(
        "Standard office staff receive a laptop configured with Windows 11, the Microsoft "
        "365 suite, and the Lapin Logistics VPN client. Warehouse and logistics staff "
        "typically work from shared desktop terminals in the operations areas; your "
        "proximity card grants physical access to the relevant terminal bays. If your "
        "role requires specialist software that is not part of the standard image, "
        "a request must be submitted to IT through the service portal before your "
        "start date so that licensing and configuration can be arranged in advance.",
        B,
    ))
    story.append(Paragraph(
        "Do not attempt to install software on your workstation without IT approval. "
        "The endpoint management system enforces an application allowlist; "
        "unauthorised installation attempts are logged and may trigger a security review. "
        "Peripheral devices (USB drives, external hard disks) must be approved by IT "
        "Security before use on any company system; see Section 5 for the full "
        "removable media policy.",
        B,
    ))

    story.append(PageBreak())

    # ------------------------------------------------------------------
    # PAGE 4 — Security Policy / AUP
    # ------------------------------------------------------------------
    story.append(Paragraph("5.  Information Security Policy and Acceptable Use", S))
    story.append(Paragraph(
        "The protection of Lapin Logistics's data, systems, and reputation is a shared "
        "responsibility. The policies in this section apply to all staff, contractors, "
        "and third parties with access to company systems, regardless of whether they "
        "are working on-site, remotely, or via a client or partner network.",
        B,
    ))

    story.append(Paragraph("Password Requirements", S))
    story.append(Paragraph(
        "Passwords must be a minimum of twelve characters and must include at least one "
        "uppercase letter, one lowercase letter, one digit, and one special character. "
        "Common dictionary words, keyboard patterns (e.g. qwerty, 123456), and any variant "
        "of your name or username are prohibited. The system enforces a history of the last "
        "twenty-four passwords; reuse within this history is blocked.",
        B,
    ))
    story.append(Paragraph(
        "Passwords must not be shared with anyone, including IT support staff. "
        "IT will never ask for your password by email, phone, or in person; any such "
        "request should be treated as a social engineering attempt and reported "
        "immediately to it-security@lapinlogistics.local. Passwords must not be written "
        "down, stored in a text file, or kept in a browser's built-in password manager "
        "unless that browser is centrally managed and the manager is approved by IT.",
        B,
    ))

    story.append(Paragraph("Removable Media and Data Transfer", S))
    story.append(Paragraph(
        "The use of personal USB drives or external storage on company equipment is "
        "prohibited without prior written authorisation from IT Security. Company data "
        "must not be transferred to personal cloud storage accounts (Dropbox, Google "
        "Drive, personal OneDrive, etc.). Approved file sharing is conducted exclusively "
        "through the company SharePoint environment or via secure file transfer links "
        "generated through the IT-approved portal.",
        B,
    ))

    story.append(Paragraph("Internet and Email Acceptable Use", S))
    story.append(Paragraph(
        "Internet access is provided for business purposes. Incidental personal use is "
        "tolerated where it does not interfere with work, consume excessive bandwidth, "
        "or involve access to content that is illegal, offensive, or in breach of this "
        "policy. Web traffic is filtered and logged; categories including gambling, adult "
        "content, and peer-to-peer file sharing are blocked at the network level.",
        B,
    ))
    story.append(Paragraph(
        "Email must be used professionally at all times. Mass-distribution emails, "
        "chain letters, and unsolicited commercial messages must not be sent from company "
        "accounts. Attachments received from external senders should be treated with "
        "caution; if in doubt, contact the IT service desk before opening. Phishing "
        "simulation exercises are conducted periodically by IT Security; results are "
        "used for targeted awareness training rather than disciplinary action.",
        B,
    ))

    story.append(Paragraph("Remote Working", S))
    story.append(Paragraph(
        "Staff approved for remote or hybrid working must connect to company systems "
        "exclusively via the Lapin Logistics VPN. The VPN client is pre-installed on "
        "company laptops; configuration details are available in the IT Remote Working "
        "Guide (intranet ref IT-RWG-006). Personal devices may not be used to access "
        "company systems unless formally enrolled in the Mobile Device Management (MDM) "
        "programme — contact IT Security to initiate enrolment.",
        B,
    ))

    story.append(PageBreak())

    # ------------------------------------------------------------------
    # PAGE 5 — Health & Safety, Contacts
    # ------------------------------------------------------------------
    story.append(Paragraph("6.  Health and Safety", S))
    story.append(Paragraph(
        "Lapin Logistics is committed to providing a safe and healthy working environment "
        "in compliance with applicable legislation in each country of operation. The "
        "company's Health &amp; Safety Policy is maintained by the Facilities team and "
        "reviewed annually; a copy is posted on the noticeboard in each building entrance "
        "and is available on the intranet under Facilities &gt; Health and Safety.",
        B,
    ))
    story.append(Paragraph(
        "All employees are required to complete the online Health &amp; Safety induction "
        "module within five working days of their start date. The module is accessible "
        "via the intranet learning portal at http://intranet.lapinlogistics.local/learning. "
        "Employees based in or regularly visiting the warehouse or cold-storage areas "
        "must additionally attend a site-specific safety briefing delivered by the "
        "Facilities team; your line manager will arrange this.",
        B,
    ))

    story.append(Paragraph("Emergency Procedures", S))
    story.append(Paragraph(
        "Fire evacuation routes are marked with green signage throughout the building. "
        "In the event of an alarm, evacuate immediately via the nearest marked exit and "
        "assemble at the designated muster point in the rear car park. Do not use lifts "
        "during an evacuation. Fire wardens are identifiable by high-visibility vests "
        "stored at each floor's fire exit. Fire drills are conducted twice per year, "
        "typically in March and September; dates are announced at least one week in "
        "advance via the all-staff email list.",
        B,
    ))
    story.append(Paragraph(
        "First-aid kits are located in the break rooms on each floor and at the warehouse "
        "office. Trained first aiders are listed on the notice board at each kit location. "
        "Workplace accidents and near-misses must be reported to Facilities Management "
        "within 24 hours using the incident report form on the intranet.",
        B,
    ))

    story.append(Paragraph("7.  Who to Contact", S))
    story.append(Paragraph(
        "The following contacts cover the most common queries during your first weeks. "
        "Full directory listings are available through Outlook or the intranet staff "
        "directory.",
        B,
    ))

    contacts = [
        ("People &amp; Culture (HR general enquiries)", "hr@lapinlogistics.local", "ext. 200"),
        ("IT Service Desk (account and hardware issues)", "it-support@lapinlogistics.local", "ext. 101"),
        ("IT Security (policy, incidents, MFA)", "it-security@lapinlogistics.local", "ext. 555"),
        ("Facilities Management (building, parking, access cards)", "facilities@lapinlogistics.local", "ext. 310"),
        ("Payroll", "payroll@lapinlogistics.local", "ext. 220"),
        ("Health &amp; Safety", "safety@lapinlogistics.local", "ext. 315"),
        ("Canteen and Catering", "catering@lapinlogistics.local", "ext. 250"),
    ]

    for label, email, ext in contacts:
        story.append(Paragraph(
            f"<b>{label}</b>: {email} &nbsp;&nbsp; {ext}",
            I,
        ))

    story.append(Spacer(1, 0.6 * cm))
    story.append(Paragraph(
        "Lapin Logistics — crisp carrot distribution since 1973. "
        "HR-ORI-001 Rev 4.2 | Approved by People &amp; Culture and IT Security. "
        "Not for external distribution.",
        F,
    ))

    doc.build(story)
    return path


# ---------------------------------------------------------------------------
# carrot_quality_standards.pdf
# ---------------------------------------------------------------------------

def make_carrot_quality_standards(outdir: str) -> str:
    """
    Internal quality standards for carrot grading.
    """
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import cm

    path = os.path.join(outdir, "carrot_quality_standards.pdf")

    doc = SimpleDocTemplate(
        path,
        pagesize=A4,
        leftMargin=2.5 * cm,
        rightMargin=2.5 * cm,
        topMargin=2.5 * cm,
        bottomMargin=2.5 * cm,
        title="Carrot Quality Standards — Internal Specification",
        author="Lapin Logistics Operations",
        subject="Quality Assurance",
    )

    styles = _build_styles()
    S = styles["SectionHeading"]
    B = styles["Body"]
    I = styles["BodyIndent"]
    F = styles["Footer"]
    T = styles["DocTitle"]
    Sub = styles["DocSubtitle"]

    story = []

    story.append(Paragraph("Lapin Logistics", T))
    story.append(Paragraph("Carrot Quality Standards — Internal Specification", T))
    story.append(Paragraph(
        "Document Ref: OPS-QA-042 &nbsp;|&nbsp; Revision 3.1 &nbsp;|&nbsp; "
        "Effective: 2024-02-01",
        Sub,
    ))

    story.append(Paragraph("1.  Purpose and Scope", S))
    story.append(Paragraph(
        "This specification defines the minimum quality standards applicable to all "
        "carrots handled, stored, or distributed by Lapin Logistics on behalf of its "
        "wholesale and retail clients. It applies to produce received from contracted "
        "growers, produce received from spot-market purchases, and any re-graded or "
        "repackaged stock. All operations staff and quality assurance inspectors are "
        "required to be familiar with this document.",
        B,
    ))
    story.append(Paragraph(
        "This document should be read in conjunction with OPS-QA-040 (Cold-Chain "
        "Management Procedures) and OPS-QA-041 (Supplier Approved List and Audit "
        "Schedule). Any conflict between this specification and client-specific "
        "requirements should be escalated to the Quality Manager; client requirements "
        "take precedence where they exceed the standards set out here.",
        B,
    ))

    story.append(Paragraph("2.  Grading Criteria", S))
    story.append(Paragraph(
        "Lapin Logistics grades incoming carrots into three categories: Grade A (premium), "
        "Grade B (standard commercial), and Grade C (processing/animal feed). Grading "
        "is performed at the point of intake by a trained QA inspector and again at the "
        "point of outbound packing. Discrepancies between intake and outbound grades "
        "must be documented on the batch deviation form (OPS-FM-017).",
        B,
    ))

    story.append(Paragraph("Grade A — Premium", S))
    story.append(Paragraph(
        "Grade A carrots must be fresh, firm, and free from visible damage, disease, "
        "pest infestation, or soil contamination beyond minor surface soiling. "
        "Minimum diameter at the shoulder: 20 mm. Minimum length: 10 cm. "
        "Maximum length: 25 cm. Colour must be uniformly orange; forked, cracked, "
        "or misshapen specimens are excluded. Moisture content must not exceed 88% "
        "by fresh weight. Maximum permissible external bruising: none.",
        B,
    ))

    story.append(Paragraph("Grade B — Standard Commercial", S))
    story.append(Paragraph(
        "Grade B carrots meet the same minimum freshness requirements as Grade A but "
        "may exhibit minor cosmetic defects including shallow surface cracks, slight "
        "forking, or minor colour variation. Minimum diameter at the shoulder: 16 mm. "
        "Length range: 8–28 cm. Bruising area not to exceed 5% of visible surface. "
        "Grade B produce is suitable for wholesale grocery and catering channels.",
        B,
    ))

    story.append(Paragraph("Grade C — Processing", S))
    story.append(Paragraph(
        "Grade C covers carrots not meeting Grade B criteria but still safe and suitable "
        "for human consumption when processed. This includes over-size, undersized, "
        "heavily forked, or cosmetically damaged specimens that retain sound flesh. "
        "Grade C produce is directed to processing clients (juicing, prepared vegetable "
        "manufacturers) or, where not suitable for food use, to approved animal feed "
        "suppliers. Rot, mould, or pest damage is grounds for rejection regardless of "
        "grade; such produce is disposed of under the waste disposal protocol (OPS-WD-003).",
        B,
    ))

    story.append(Paragraph("3.  Intake Inspection Procedure", S))
    story.append(Paragraph(
        "On arrival at any Lapin Logistics facility, each delivery must be accompanied "
        "by a supplier delivery note and, for contracted growers, a completed field "
        "record form (OPS-FM-005). The intake inspector checks the vehicle temperature "
        "log, verifies the delivery note against the purchase order, and draws a random "
        "sample of not fewer than twenty individual carrots from a minimum of three "
        "separate positions in the load (top, middle, and bottom of the largest "
        "accessible section).",
        B,
    ))
    story.append(Paragraph(
        "Each sampled carrot is inspected visually and by hand. Temperature of the load "
        "at the time of intake is recorded with a calibrated probe thermometer; "
        "acceptable range is 1°C to 7°C. Loads outside this range are quarantined "
        "pending a decision by the Quality Manager. Results are entered into the "
        "Logistics Management System (LMS) within two hours of intake completion.",
        B,
    ))

    story.append(Paragraph("4.  Storage and Cold-Chain Requirements", S))
    story.append(Paragraph(
        "All Grade A and Grade B produce must be stored at between 1°C and 4°C with "
        "relative humidity of 90–95%. Temperature and humidity in each storage cell "
        "are logged automatically at fifteen-minute intervals by the building management "
        "system. Any deviation lasting more than thirty minutes triggers an automated "
        "alert to the duty supervisor. Grade C produce awaiting transfer to processing "
        "clients may be held at up to 7°C for a maximum of 48 hours.",
        B,
    ))
    story.append(Paragraph(
        "Stock rotation follows strict first-in, first-out (FIFO) principles enforced "
        "through the LMS. Pallet locations are assigned by the system at intake and "
        "must not be manually overridden without authorisation from the Warehouse Manager. "
        "Maximum storage duration before outbound dispatch: Grade A, 14 days from harvest "
        "date; Grade B, 21 days from harvest date.",
        B,
    ))

    story.append(Paragraph("5.  Packaging and Labelling", S))
    story.append(Paragraph(
        "Outbound product must be packed in approved cartons or nets as specified in the "
        "relevant client contract. Each outer carton or net bag must bear a label "
        "compliant with EU Regulation (EU) 1169/2011 displaying at minimum: product "
        "name and variety, country of origin, grade, net weight, and the Lapin Logistics "
        "batch reference number (format: LL-YYYYMMDD-XXX). Batch reference numbers are "
        "generated by the LMS at the point of outbound picking.",
        B,
    ))

    story.append(Spacer(1, 0.6 * cm))
    story.append(Paragraph(
        "OPS-QA-042 Rev 3.1 | Lapin Logistics Operations Quality Assurance | "
        "Not for external distribution. Approved by: Quality Manager.",
        F,
    ))

    doc.build(story)
    return path


# ---------------------------------------------------------------------------
# q3_logistics_review.pdf
# ---------------------------------------------------------------------------

def make_q3_logistics_review(outdir: str) -> str:
    """
    Q3 internal logistics performance review.
    """
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import cm

    path = os.path.join(outdir, "q3_logistics_review.pdf")

    doc = SimpleDocTemplate(
        path,
        pagesize=A4,
        leftMargin=2.5 * cm,
        rightMargin=2.5 * cm,
        topMargin=2.5 * cm,
        bottomMargin=2.5 * cm,
        title="Q3 2024 Logistics Performance Review",
        author="Lapin Logistics Operations",
        subject="Internal Performance Review",
    )

    styles = _build_styles()
    S = styles["SectionHeading"]
    B = styles["Body"]
    I = styles["BodyIndent"]
    F = styles["Footer"]
    T = styles["DocTitle"]
    Sub = styles["DocSubtitle"]

    story = []

    story.append(Paragraph("Lapin Logistics", T))
    story.append(Paragraph("Q3 2024 Logistics Performance Review", T))
    story.append(Paragraph(
        "Internal — Management Distribution Only &nbsp;|&nbsp; "
        "Period: 01 July – 30 September 2024 &nbsp;|&nbsp; Prepared by: Operations",
        Sub,
    ))

    story.append(Paragraph("Executive Summary", S))
    story.append(Paragraph(
        "Q3 2024 was a broadly positive quarter for Lapin Logistics operations, with "
        "on-time delivery performance reaching 96.4% across all routes, an improvement "
        "of 1.8 percentage points on Q2. Total tonnage handled across the network "
        "increased by 7.2% year-on-year, driven primarily by new contracts with three "
        "supermarket groups in the Polish and Czech markets. Fleet utilisation averaged "
        "83%, up from 79% in Q2 and the highest figure recorded since Q1 2022.",
        B,
    ))
    story.append(Paragraph(
        "The quarter was not without challenge. A prolonged heat event in late August "
        "placed additional strain on cold-chain management across the southern routes; "
        "two loads were rejected by clients on temperature grounds, both attributed to "
        "a failure of refrigeration units on vehicles subsequently taken out of service "
        "for repair. The incident is reviewed in Section 4. A total of fourteen formal "
        "client complaints were received during the quarter, a reduction of three "
        "compared with Q2; details are summarised in Section 5.",
        B,
    ))

    story.append(Paragraph("1.  Volume and Route Performance", S))
    story.append(Paragraph(
        "The Strasbourg hub processed 48,312 tonnes of fresh produce in Q3, compared "
        "to 44,810 tonnes in Q3 2023. The Vienna hub processed 21,640 tonnes, "
        "Warsaw 18,903 tonnes, and Bucharest 12,470 tonnes. Cross-hub transfer volume "
        "increased by 11% as a result of re-routing decisions made to mitigate the "
        "August heat event, adding approximately €38,000 in fuel and handling costs "
        "that were partially recovered through fuel surcharge clauses in the relevant "
        "client contracts.",
        B,
    ))
    story.append(Paragraph(
        "Route SR-12 (Strasbourg to Stuttgart distribution loop) continued to "
        "underperform against KPI; average on-time delivery was 91.2% against a target "
        "of 95%. Root cause analysis identified persistent congestion at the B28 "
        "junction on Tuesdays and Wednesdays as the primary factor. The route planning "
        "team has modelled an amended departure window (shifting the primary run from "
        "05:30 to 04:15) that is projected to recover approximately two-thirds of the "
        "lost time; this change is scheduled for implementation in week 42.",
        B,
    ))

    story.append(Paragraph("2.  Fleet Status", S))
    story.append(Paragraph(
        "The active fleet comprised 214 refrigerated vehicles at the end of Q3, "
        "following the addition of seven new units delivered in August and the "
        "retirement of four units that had reached end-of-service life. Three vehicles "
        "are currently off-road pending major repair (two refrigeration unit "
        "replacements, one chassis structural work); all three are expected to return "
        "to service by the end of week 44. Fleet age profile: 31% of vehicles are "
        "less than three years old, 42% are three to six years old, and 27% are over "
        "six years old. The capital expenditure plan for 2025 includes provision for "
        "the replacement of a further twelve older units.",
        B,
    ))

    story.append(Paragraph("3.  Supplier and Intake Performance", S))
    story.append(Paragraph(
        "Seventeen contracted growers supplied produce to the Lapin Logistics network "
        "in Q3. Intake rejection rates remained low at an average of 1.4% of "
        "delivered tonnage across all suppliers, consistent with Q2. Two suppliers "
        "recorded elevated rejection rates: Domaine Agrar GmbH (4.1%, primarily "
        "size non-conformance) and Ferme des Vallées SARL (3.7%, colour and "
        "surface quality defects linked to an early harvest decision in response to "
        "the heat event). Both suppliers have been notified and improvement plans "
        "are being discussed with the procurement team.",
        B,
    ))
    story.append(Paragraph(
        "Spot-market purchases accounted for 8.3% of total intake volume in Q3, "
        "up from 5.9% in Q2, reflecting tighter contracted supply during the heat "
        "period. Spot-market produce carried an average cost premium of 12% over "
        "contracted supply; the full cost impact was approximately €94,000 against "
        "budget. The procurement team has initiated discussions with two additional "
        "growers with a view to expanding contracted capacity ahead of the 2025 season.",
        B,
    ))

    story.append(Paragraph("4.  Cold-Chain Incident Review", S))
    story.append(Paragraph(
        "On 22 August, vehicle LL-V-0187 on the Vienna to Bratislava run experienced "
        "a refrigeration unit failure approximately 90 minutes into the route. The "
        "driver followed the established breakdown procedure, notifying depot control "
        "and pulling over to a safe location. A replacement vehicle was dispatched but "
        "arrived 2 hours 40 minutes after the initial call. During the interval the "
        "load temperature rose to 9.4°C. The receiving client rejected the load on "
        "temperature grounds; the estimated write-off value was €11,200.",
        B,
    ))
    story.append(Paragraph(
        "A second incident occurred on 28 August involving vehicle LL-V-0203 on the "
        "Bucharest to Sofia corridor. A defective door seal allowed ambient temperature "
        "ingress that was not detected until a mid-route check by the driver. "
        "The load temperature had reached 8.1°C; the load was partially salvaged "
        "(Grade B and C produce retained for processing clients, Grade A produce "
        "rejected), with an estimated loss of €6,800. Both vehicles have since had "
        "refrigeration units replaced and door seals inspected across the wider fleet. "
        "A monthly door-seal inspection checklist has been added to the pre-departure "
        "vehicle check procedure.",
        B,
    ))

    story.append(Paragraph("5.  Client Complaints Summary", S))
    story.append(Paragraph(
        "Fourteen formal complaints were received in Q3 via the client services team. "
        "Breakdown by category: delivery timing (5), product quality (4), documentation "
        "error (3), temperature deviation (2). Of the fourteen, eleven have been closed "
        "with agreed resolution; three remain open pending final client sign-off. "
        "No complaints escalated to formal dispute or legal proceedings during the "
        "quarter. The client satisfaction index (based on the quarterly survey sent to "
        "key accounts) was 7.8 out of 10, unchanged from Q2.",
        B,
    ))

    story.append(Paragraph("6.  Outlook — Q4 2024", S))
    story.append(Paragraph(
        "Q4 is historically the network's highest-volume quarter, driven by pre-Christmas "
        "demand from retail and catering clients. Volume is forecast at approximately "
        "115,000 tonnes across all hubs, a 9% increase on Q4 2023. Key risks include "
        "adverse winter weather affecting road networks, the two vehicles still off-road "
        "for repair, and tighter driver availability over the December holiday period. "
        "Contingency planning for winter disruption is under review by the Operations "
        "Management team and will be circulated to hub managers by the end of October.",
        B,
    ))

    story.append(Spacer(1, 0.6 * cm))
    story.append(Paragraph(
        "Q3 2024 Logistics Performance Review | Lapin Logistics Operations | "
        "Internal — Management Distribution Only. Not for external distribution.",
        F,
    ))

    doc.build(story)
    return path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = parse_args()
    outdir = args.outdir

    # Verify reportlab is available before creating any directories
    try:
        import reportlab  # noqa: F401
    except ImportError as exc:
        print(f"[ERROR] Missing dependency: {exc}", file=sys.stderr)
        print("Install with: pip install reportlab", file=sys.stderr)
        sys.exit(1)

    os.makedirs(outdir, exist_ok=True)

    files = []

    path = make_it_orientation(outdir)
    print(f"[gen-pdfs] wrote {path}")
    files.append(path)

    path = make_carrot_quality_standards(outdir)
    print(f"[gen-pdfs] wrote {path}")
    files.append(path)

    path = make_q3_logistics_review(outdir)
    print(f"[gen-pdfs] wrote {path}")
    files.append(path)

    print(f"[gen-pdfs] done — {len(files)} files written to {outdir}")


if __name__ == "__main__":
    main()
