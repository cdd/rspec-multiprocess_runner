# docker build -t mpr .
#
# Test:
# docker run mpr
#
# For development:
# docker run -it -v $PWD:/tmp/src -w /tmp/src mpr bash
ARG VERSION
FROM ruby:${VERSION}
LABEL maintainer="cdd.com"

WORKDIR /app

COPY Gemfile .
RUN mkdir -p lib/rspec/multiprocess_runner
COPY lib/rspec/multiprocess_runner/version.rb ./lib/rspec/multiprocess_runner/version.rb
COPY *.gemspec .

RUN bundle install -j 4

COPY . ./

CMD ["rake", "spec"]
