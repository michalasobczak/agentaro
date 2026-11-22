# Spec 046, G3/R2: text made ready to be spoken in the Naturalna conversation mode — times, dates and numbers as
# words, links, paths and ids left out. Polish and English; forms it does not know are left as they are.
module SpeechText
  PL_ONES = %w[zero jeden dwa trzy cztery pięć sześć siedem osiem dziewięć dziesięć jedenaście dwanaście trzynaście czternaście
               piętnaście szesnaście siedemnaście osiemnaście dziewiętnaście].freeze
  PL_TENS = [ nil, nil, "dwadzieścia", "trzydzieści", "czterdzieści", "pięćdziesiąt", "sześćdziesiąt", "siedemdziesiąt", "osiemdziesiąt", "dziewięćdziesiąt" ].freeze
  PL_HUNDREDS = [ nil, "sto", "dwieście", "trzysta", "czterysta", "pięćset", "sześćset", "siedemset", "osiemset", "dziewięćset" ].freeze
  PL_HOURS = %w[zero pierwsza druga trzecia czwarta piąta szósta siódma ósma dziewiąta dziesiąta jedenasta dwunasta trzynasta czternasta
                piętnasta szesnasta siedemnasta osiemnasta dziewiętnasta dwudziesta].freeze
  PL_DAYS = %w[pierwszego drugiego trzeciego czwartego piątego szóstego siódmego ósmego dziewiątego dziesiątego jedenastego dwunastego
               trzynastego czternastego piętnastego szesnastego siedemnastego osiemnastego dziewiętnastego dwudziestego].freeze
  PL_MONTHS = %w[stycznia lutego marca kwietnia maja czerwca lipca sierpnia września października listopada grudnia].freeze
  PL_OBLIQUE = /\b(o|do|od|po|przed|około|koło|między|na)\s+\z/i # "o 15:10" → "o piętnastej dziesięć"
  EN_ONES = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen].freeze
  EN_TENS = [ nil, nil, "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety" ].freeze
  EN_MONTHS = %w[January February March April May June July August September October November December].freeze

  URL = %r{\b(?:https?://|www\.)\S+?(?=[.,;:!?)]*(?:\s|\z))}i # the sentence's own full stop stays
  PATH = %r{(?<![\p{L}\p{N}])(?:~|\.{1,2})?/(?:[\w.@-]+/)*[\w.@-]+/?|\b[\w-]+(?:/[\w.-]+)+\.\w{1,5}\b}
  IDS = /\s*\((?:id|run|attempt|decision|próba)\s*#?\d+\)|\b(?:id|#)\s*\d+\b/i

  def self.prepare(text, language)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("").gsub(URL, "").gsub(PATH, "").gsub(IDS, "")
    text = language == "en" ? english(text) : polish(text)
    text.gsub(/\s+([.,!?;:])/, "\\1").gsub(/([,;:])(?=[.!?])/, "").squeeze(" ").strip
  end

  # --- Polish ---------------------------------------------------------------------------------------------------------

  def self.polish(text)
    text = text.gsub(/\b(\d{4})-(\d{2})-(\d{2})\b/) do
      day, month = $3.to_i, $2.to_i
      day.between?(1, 31) && month.between?(1, 12) ? "#{pl_day(day)} #{PL_MONTHS[month - 1]}" : $&
    end
    text = text.gsub(/\b([01]?\d|2[0-3]):([0-5]\d)\b/) do
      hour, minute = $1.to_i, $2.to_i
      oblique = $`.match?(PL_OBLIQUE)
      [ pl_hour(hour, oblique), (minute.zero? ? nil : (minute < 10 ? "zero #{pl_number(minute)}" : pl_number(minute))) ].compact.join(" ")
    end
    text = text.gsub(/\b(\d{1,3})\s?%/) { "#{pl_number($1.to_i)} procent" }
    text.gsub(/(?<![\p{L}\d.,:\/-])(\d{1,3})(?![\p{L}\d]|[.,:]\d)/) { pl_number($1.to_i) }
  end

  def self.pl_number(n)
    return PL_ONES[n] if n < 20
    return [ PL_TENS[n / 10], (PL_ONES[n % 10] unless (n % 10).zero?) ].compact.join(" ") if n < 100

    [ PL_HUNDREDS[n / 100], (pl_number(n % 100) unless (n % 100).zero?) ].compact.join(" ")
  end

  def self.pl_hour(hour, oblique)
    words = hour <= 20 ? [ PL_HOURS[hour] ] : [ "dwudziesta", PL_HOURS[hour - 20] ]
    return words.join(" ") unless oblique

    words.map { |w| w == "zero" ? w : w.sub(/ga\z/, "giej").sub(/cia\z/, "ciej").sub(/a\z/, "ej") }.join(" ")
  end

  def self.pl_day(day)
    return PL_DAYS[day - 1] if day <= 20

    [ day < 30 ? "dwudziestego" : "trzydziestego", (PL_DAYS[(day % 10) - 1] unless (day % 10).zero?) ].compact.join(" ")
  end

  # --- English --------------------------------------------------------------------------------------------------------

  def self.english(text)
    text = text.gsub(/\b(\d{4})-(\d{2})-(\d{2})\b/) do
      day, month = $3.to_i, $2.to_i
      day.between?(1, 31) && month.between?(1, 12) ? "#{EN_MONTHS[month - 1]} #{en_number(day)}" : $&
    end
    text = text.gsub(/\b([01]?\d|2[0-3]):([0-5]\d)\b/) do
      hour, minute = $1.to_i, $2.to_i
      half = hour < 12 ? "AM" : "PM"
      twelve = (hour % 12).zero? ? 12 : hour % 12
      [ en_number(twelve), (minute.zero? ? nil : (minute < 10 ? "oh #{en_number(minute)}" : en_number(minute))), half ].compact.join(" ")
    end
    text = text.gsub(/\b(\d{1,3})\s?%/) { "#{en_number($1.to_i)} percent" }
    text.gsub(/(?<![\p{L}\d.,:\/-])(\d{1,2})(?![\p{L}\d]|[.,:]\d)/) { en_number($1.to_i) }
  end

  def self.en_number(n)
    return EN_ONES[n] if n < 20

    [ EN_TENS[n / 10], (EN_ONES[n % 10] unless (n % 10).zero?) ].compact.join("-")
  end
end
