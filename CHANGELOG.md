## 1.4.1

- Fix exit codes of the executable.

## 1.4.0

- Add `maxminddb` executable for command line usage. Usage:
  - `dart pub global activate maxminddb`
  - `maxminddb search 1.2.3.4`

## 1.3.0

- Use lint instead of pedantic.
- Deprecate non camel case fields in favor new ones.
- Deprecate `decodeData`.
- Fix lint errors.

## 1.2.0

- Make DataProviders public
- Don't crash when languages or descriptions are not in database.
- Data is now private. Data is a class only useful in one specific internal case. Therefore this change is seen as a bug fix rather than a Breaking Change.

## 1.1.0

- Fix double

## 1.0.0

- Initial version.
