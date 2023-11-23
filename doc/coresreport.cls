%
% Paddy NZ Limited
%
% Patrick Suggate, 10/03/2021 .
%
\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{consultreport}[2021/03/10 Consult Report Class]

\RequirePackage{etoolbox}

\def\consultclass{Consult report class}


%-- OPTIONS ---------------------------------------------------------------- %

% -- Coloured links -- %
\newtoggle{colorlinksoption}
\togglefalse{colorlinksoption}
\DeclareOption{colorlinks}{ \toggletrue{colorlinksoption} }

% -- Draft and final -- %
\newtoggle{draftoption}
\newtoggle{finaloption}
\togglefalse{draftoption}
\toggletrue{finaloption}
\DeclareOption{draft}{ \toggletrue{draftoption} \togglefalse{finaloption} \newcommand{\watermarkword}{DRAFT} }
\DeclareOption{final}{ \togglefalse{draftoption} \toggletrue{finaloption} }

% -- Public/private document setting -- %
\newtoggle{privateoption}
\toggletrue{privateoption}
\DeclareOption{private}{ \toggletrue{privateoption} }
\DeclareOption{public}{ \togglefalse{privateoption} }

% -- Font size -- %
\newtoggle{smallfontoption}
\togglefalse{smallfontoption}
\DeclareOption{10pt}{ \toggletrue{smallfontoption} }
\DeclareOption{11pt}{ \togglefalse{smallfontoption} }

% -- Enable more-dense packing, for some technical documents -- %
\newtoggle{packedoption}
\togglefalse{packedoption}
\DeclareOption{packed}{ \toggletrue{packedoption} }
\DeclareOption{spaced}{ \togglefalse{packedoption} }

% -- Send the unprocessed options to the base-class -- %
\DeclareOption*{%
  \PassOptionsToClass{\CurrentOption}{report}%
}

% -- End of options -- %
\ProcessOptions\relax

% -------------------------------------------------------------------------- %


% -- Extend the ``report'' class -- %
\iftoggle{smallfontoption}{
  \LoadClass[a4paper,10pt]{report}
}{
  \LoadClass[a4paper,11pt]{report}
}


% -- Tag a document as private, if necessary -- %
\iftoggle{privateoption}{%
  \newcommand{\private}{\sgi{Commercial in Confidence}}
}{%
  \newcommand{\private}{}
}


% -- Colour settings -- %
\RequirePackage[usenames,dvipsnames]{color}
\definecolor{ConsultGrey}{rgb}{0.3555,0.3666,0.3555} % { , , }
% \definecolor{ConsultBlue}{rgb}{0.180,0.365,0.475}
\definecolor{ConsultBlue}{rgb}{0.169,0.471,1.0}
\definecolor{ConsultGreen}{rgb}{0.761,0.847,0.271}

\newcommand{\sgi}{\it\textcolor{ConsultGrey}}

% -- Consult logo colour -- %
\newcommand{\ConsultLogo}{
  \raisebox{-2.5mm}[4mm][5mm]{
    \hspace{3mm}\mbox{
      Patrick Suggate
%       \includegraphics[width=28mm]{images/consult}
  }}{\hspace{-3mm}}}
%   \definecolor{ConsultTheme}{rgb}{0.180,0.365,0.475}
  \definecolor{ConsultTheme}{rgb}{0.169,0.471,1.0}

% -- Set the page dimensions and margins -- %
\RequirePackage{geometry}
\iftoggle{packedoption}{%
  \geometry{a4paper, margin=0.7in, top=1.0in, bottom=1.0in}
}{%
  \geometry{a4paper, margin=1in, top=1.25in, bottom=1.25in}
}
\RequirePackage[parfill]{parskip}


% -- Add the Consult logo to each page -- %
\RequirePackage{eso-pic}
\RequirePackage[final]{graphicx}


% -- Setup default document font -- %
\usepackage{amsmath, amsfonts, amsthm, amssymb}
\usepackage[T1]{fontenc}
\renewcommand{\familydefault}{\sfdefault}
\RequirePackage{helvet}
% Add in some useful symbols, that are missing in the selected font
\usepackage{textcomp}
\renewcommand{\textrightarrow}{$\rightarrow$}
\renewcommand{\textleftarrow}{$\leftarrow$}
\renewcommand{\textuparrow}{$\uparrow$}
\renewcommand{\textdownarrow}{$\downarrow$}


% -- Do we need to place watermarks on all pages? -- %
% TODO: this can break images
\ifdef{\watermarkword}{
    \RequirePackage{draftwatermark}
    \SetWatermarkText{\watermarkword}
    \SetWatermarkScale{1}
    \SetWatermarkLightness{0.95}
    %\ use package[printwatermark]{xwatermark}
    %\ newwatermark[allpages,color=red!50,angle=45,scale=3,xpos=0,ypos=0]{DRAFT}
}{}


% -- Define extra titlepage stuff -- %
\newcommand{\authors}[1]{\newcommand{\@authors}{#1}}
\newcommand{\version}[1]{\newcommand{\@version}{#1}}
\newcommand{\subtitle}[1]{\newcommand{\@subtitle}{#1}}
\newcommand{\reportname}[1]{\newcommand{\@reportname}{#1}}
\newcommand{\reportnumber}[1]{\newcommand{\@reportnumber}{#1}}


% -- Setup page numbering -- %
\AtBeginDocument{
  \pagenumbering{arabic}

  \RequirePackage{lastpage}
  \RequirePackage{fancyhdr}
  \pagestyle{fancy}
  \fancyhf{} % clear all header and footer fields

  \renewcommand{\headheight}{28pt}
  \renewcommand{\footskip}{24pt}
  \renewcommand{\headrulewidth}{0.4pt}
  \renewcommand{\footrulewidth}{0.4pt}% default is 0pt

  \rfoot{\sgi{Page \thepage\ of \pageref*{LastPage}}}
  \lfoot{\sgi{{\textcopyright}~\the\year~\Consult}}

  \RequirePackage{xstring}
  % If filename was not specified then assume it from the jobname
  \ifdef{\@reportname}{}{\reportname{\jobname}}
  % If report number not set then extract it from the filename
  \ifdef{\@reportnumber}{}{\reportnumber{\StrBefore*{\@reportname}{_}}}

  \cfoot{\private}
  \lhead{\small{\@reportname}}
  \chead{\ifdef{\@version}{\ v\@version}{}}
  \rhead{\ConsultLogo}

}


% -- Render the title-page -- %
\renewcommand{\maketitle}{%
  \iftoggle{packedoption}{%
    \vspace*{-7mm}
  }{%
    \vspace*{3mm}
  }
  {\fontsize{24}{30}\selectfont{\par{\textcolor{ConsultGrey}{\@title}}\par}}
  \vspace{5mm}\par
  \textcolor{ConsultGrey}{
  \begin{tabular}{ll}
    \ifdef{\@authors}{\textbf{Contributors:} & \@authors}{\ifdef{\@author}{\textbf{Author:} & \@author}{}} \\
    \ifdef{\@date}{\textbf{Date:} & \@date}{} \\
    \ifdef{\@version}{\textbf{Version:} & \@version}{}
  \end{tabular}
  }
}


% -- Adjust table of contents -- %
% NOTE: refer to:
%   http://ctan.unsw.edu.au/macros/latex/contrib/tocloft/tocloft.pdf
\RequirePackage{tocloft}
% Fix size and color of heading, and reduce the vertical gap after the word "Contents"
\renewcommand{\contentsname}{\vspace{-9mm}\bfseries\Large\textcolor{ConsultGrey}{Contents}\vspace{-9mm}}
\renewcommand{\cftpartleader}{\cftdotfill{\cftdotsep}}
\renewcommand{\cftchapleader}{\cftdotfill{\cftdotsep}}
\renewcommand{\cftsecleader}{\cftdotfill{\cftdotsep}}
\renewcommand{\cftbeforepartskip}{4mm}
\renewcommand{\cftbeforechapskip}{2mm}
\renewcommand{\cftbeforesecskip}{1mm}
\renewcommand{\cftbeforesubsecskip}{1mm}
% And try to maintain correct page numbering representation on bottom of contents pages
\patchcmd{\tableofcontents}{\thispagestyle{plain}}{\thispagestyle{fancy}}{}{}
\AtBeginDocument{\addtocontents{toc}{\protect\thispagestyle{fancy}}} 


% -- Adjust the properties for figures (and the list of them) -- %
\renewcommand{\listfigurename}{\vspace{-9mm}\bfseries\Large\textcolor{ConsultGrey}{List of Figures}\vspace{-9mm}}

\renewcommand{\listtablename}{\vspace{-9mm}\bfseries\Large\textcolor{ConsultGrey}{List of Tables}\vspace{-9mm}}

\RequirePackage[font={color=ConsultGrey,small}]{caption}

\RequirePackage{graphicx}
\renewcommand{\floatpagefraction}{.8}%


% -- Section heading settings -- %
\RequirePackage{titlesec}
% Special fix for colourising \part, as \titleformat would break the formatting when attempted
% TODO: still necessary?
\let\partbackup\part
\renewcommand{\part}[1]{{\color{ConsultGrey}\partbackup{#1}}}

% -- Packed vs spaced-out heading sizes -- %
\iftoggle{packedoption}{%
  \titleformat{\chapter}{\bfseries\Large\color{ConsultGrey}}{\thechapter}{5mm}{}
  \titleformat{\section}{\bfseries\large\color{ConsultGrey}}{\thesection}{3mm}{}
  \titleformat{\subsection}{\bfseries\color{ConsultGrey}}{\thesubsection}{3mm}{}
  \titleformat{\subsubsection}{\bfseries\small\color{ConsultGrey}}{\thesubsubsection}{3mm}{}
}{%
  \titleformat{\chapter}{\bfseries\LARGE\color{ConsultGrey}}{\thechapter}{5mm}{}
  \titleformat{\section}{\bfseries\Large\color{ConsultGrey}}{\thesection}{4mm}{}
  \titleformat{\subsection}{\bfseries\large\color{ConsultGrey}}{\thesubsection}{4mm}{}
  \titleformat{\subsubsection}{\bfseries\small\color{ConsultGrey}}{\thesubsubsection}{4mm}{}
}

% -- Some tweaking to the layout-rules for headings -- %
% \titlespacing{<command>}{<left>}{<before-sep>}{<after-sep>}
\titlespacing{\chapter}{0mm}{5mm}{3mm} % Was 0,12,3 before changing \parskip
\titlespacing{\section}{0mm}{2mm}{3mm} % Was 0,7,3 before changing \parskip
% Prevent \chapter from starting a new page
\patchcmd{\chapter}{\if@openright\cleardoublepage\else\clearpage\fi}{\par}{}{}
% Prevent \part and \chapter from breaking the page style on the page that has the new chapter heading
\patchcmd{\partbackup}{\thispagestyle{plain}}{\thispagestyle{fancy}}{}{}
\patchcmd{\chapter}{\thispagestyle{plain}}{\thispagestyle{fancy}}{}{}

% -- Allow \subsubsection to produce a number throughout the document -- %
% NOTE: that this is independent of the number of levels displayed in the ToC
\setcounter{secnumdepth}{3}


% -- Change color of bullets -- %
\renewcommand\labelitemi{\color{ConsultGrey}\textbullet}
\renewcommand\labelitemii{\color{ConsultGrey}\normalfont\bfseries \textendash}
\renewcommand\labelitemiii{\color{ConsultGrey}\textasteriskcentered}
\renewcommand\labelitemiv{\color{ConsultGrey}\textperiodcentered}


% -- Set the row-spacing between rows of each table -- %
\iftoggle{packedoption}{%
  \renewcommand{\arraystretch}{1.2}
}{%
  \renewcommand{\arraystretch}{1.35}
}


% -- Formatting for code listings -- %
% NOTE: When using `pandoc`, it will use its own built-in code formatters
% TODO: Finish setting up the code-listings settings.
% Pass ``final'' to the ``listings'' package, or else it suppresses all output
\PassOptionsToPackage{final}{listings}

\RequirePackage{listings}
\lstset{
  basicstyle=\small\ttfamily,
%   stringstyle=\color{ConsultTheme},
  commentstyle=\ttfamily\color{ConsultGrey},
%   numbers=left, 
%   numberstyle=\small, 
%   numbersep=8pt, 
  xleftmargin=12pt,
  xrightmargin=12pt,
  frame=single, 
  framexrightmargin=4pt,
  framexleftmargin=4pt,
  framextopmargin=4pt,
  framexbottommargin=4pt,
  language=Haskell
}


% -- Optional bibliography -- %
% Fix bibliography environment
% Allow it to be added to the table of contents
\patchcmd{\thebibliography}{\chapter*{\bibname}}{\chapter{\bibname}}{}{}


% -- Change colour of links, including table of contents -- %
% TODO: finish customising these link-colours
\iftoggle{colorlinksoption}{
  \definecolor{ConsultLinkInternalColor}{rgb}{0.75,0,0} % Dark Red
  \definecolor{ConsultLinkUrlColor}{rgb}{0,0,0.75} % Dark Blue
  \definecolor{ConsultLinkCite}{rgb}{0,0.75,0} % Dark Green
}{
  \definecolor{ConsultLinkInternalColor}{rgb}{0,0,0} % Black
  \definecolor{ConsultLinkUrlColor}{rgb}{0,0,0} % Black
  \definecolor{ConsultLinkCite}{rgb}{0,0,0} % Black
}
% Must be last package included unless modifying it
% \RequirePackage[colorlinks, linktoc=all, linkcolor=ConsultLinkInternalColor, urlcolor=ConsultLinkUrlColor, citecolor=ConsultLinkCite, final]{hyperref}

\RequirePackage[colorlinks, linktoc=all, linkcolor=ConsultTheme, urlcolor=ConsultTheme, citecolor=ConsultTheme, final]{hyperref}


% -- Various trademarks -- %
% TODO:
\newcommand{\Consult}{Consult}
% \newcommand\textmiddlescript[1]{$\vcenter{\hbox{\scriptsize  #1}}$}
% \newcommand{\Consult}{Consult\textmiddlescript{nz}}
% \newcommand{\Consult}{Consult\textsuperscript{\textregistered}}


%
% Special-purpose tables
% -------------------------------------------------------------------------- %
\RequirePackage{colortbl}

% Centered in Table Cell (formatting, text)
\newcommand{\ctc}[2]{\multicolumn{1}{#1}{{\bf#2}}}

% For longtable, equivalent to \hline \hline in traditional tabular environment
\newcommand{\lline}[1]{\hline\multicolumn{#1}{c}{}\\[-1.3em]\hline}

\newcommand{\sectiondiv}[1]{\multicolumn{3}{|>{\columncolor[rgb]{0.95,0.95,1}}c|}{#1}}

% Boxy tables for listing and defining parameters
\newcommand{\paramlistheader}{
  \ctc{|c|}{Parameter} & \ctc{c|}{Type} & \ctc{c|}{Description} \\
  \lline{3}
}
\newenvironment{paramlist}[2]
{
  \begin{longtable}{|l|l|p{#1}|}
    \caption{#2} \\
    \hline
    \paramlistheader \endfirsthead
    \hline
    \multicolumn{3}{|r|}{\tablename\ \thetable{} -- continued from previous page} \\
    \hline
    \paramlistheader \endhead
    \hline \multicolumn{3}{|r|}{{Continued on next page}} \\
    \hline
    \endfoot
    \endlastfoot
}
{
    \end{longtable}
}
% -------------------------------------------------------------------------- %
